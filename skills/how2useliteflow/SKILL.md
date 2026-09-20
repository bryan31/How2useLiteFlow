---
name: how2useliteflow
description: 当用户询问、使用、设计、排查或升级 LiteFlow 时启用。覆盖 LiteFlow 2.16.2 的接入与配置、组件、EL、上下文、执行器、脚本、规则源、Rule-DB、监控、动态构建、测试、源码，以及基于 AgentScope 2 的 liteflow-agent、模型、工具、MCP、会话、事件、HITL、Skills、Harness 和 A2A。也用于识别并迁移旧 liteflow-react-agent / ReActAgentComponent 用法。
metadata:
  version: "2.1.0"
---

# LiteFlow 2.16.2 助手

帮助用户正确使用 LiteFlow，并在信息不足时通过本地源码核实，而不是猜测 API、配置项、默认值或运行行为。

## 版本边界

- 知识基线为 LiteFlow `2.16.2`，依据源码、仓库内三份 guide 和官网 2.16.X 文档核验，日期为 `2026-09-19`。源码快照及覆盖口径见 [coverage.md](references/coverage.md)。
- Maven 示例统一使用 `2.16.2`。发布准备完成不等于所有镜像已同步；依赖无法解析时检查实际仓库，或从匹配源码执行 `mvn install -DskipTests`，不要自动退回旧版本。
- 核心支持 JDK 8～25；Agent 要求 JDK 17+，源码管理 AgentScope Java `2.0.3`。
- Agent 业务组件统一继承 `com.yomahub.liteflow.agent.harness.component.HarnessAgentComponent`，来自 `liteflow-agent-core`。旧 `AgentComponent`、`ReActAgentComponent` 和独立 `liteflow-agent-harness` 不用于新项目。
- Rule-DB、Metrics、节点执行生命周期在 2.16.1 引入，2.16.2 继续支持。

## 回答流程

1. 每次会话首次使用本 Skill 时，运行 `scripts/version-check.sh`。退出码 `1` 表示检查失败，脚本会输出简短诊断，但不影响继续作答；退出码 `2` 表示远端 Skill 有更新，告知用户并在获得同意后执行脚本建议的更新命令。
2. 先按下方知识地图只读取与问题直接相关的 reference。简单问题可直接使用高频速查，不要一次加载全部文件。
3. 遇到版本敏感、reference 未覆盖、用户要求源码依据，或不同文档说法冲突时，先运行 `scripts/source-lookup.sh path` 定位本地仓库，并核对根 POM 的 revision／AgentScope 版本与用户基线。
4. 若仓库根存在 `.codegraph/` 且命令可用，优先执行 `scripts/source-lookup.sh explore "问题或符号"`；否则使用 `grep`、`grepall`、`find`、`show` 子命令。回答源码问题时引用真实 `path:line`。
5. 本地没有源码且问题无法确认时，先征得用户同意，再运行 `scripts/source-lookup.sh clone`。用户未同意时应明确说无法确认，不得自行克隆或臆测。

网络文章、搜索摘要和模型记忆不能替代 LiteFlow 当前源码。用户明确要求联网查资料时，可把网络内容作为补充，并清楚区分“官方当前源码行为”和“外部资料说法”。

## 高频速查

### Maven 与最小接入

Spring Boot 2/3：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot-starter</artifactId>
    <version>2.16.2</version>
</dependency>
```

Spring Boot 4 改用 `liteflow-spring-boot4-starter`。纯 Spring 用 `liteflow-spring`，Solon 用 `liteflow-solon-plugin`。规则文件场景至少配置：

```properties
liteflow.rule-source=config/flow.el.xml
```

### EL 算子

| 需求 | 写法 | 说明 |
|---|---|---|
| 串行 | `THEN(a, b, c)` | 别名 `SER` |
| 并行 | `WHEN(a, b, c)` | 别名 `PAR`；可配 `any`、`must`、`percentage`、`ignoreError`、超时 |
| 条件 | `IF(x, a, b)` | 支持 `ELIF` / `ELSE` |
| 多路选择 | `SWITCH(x).to(a, b, c)` | x 返回目标 nodeId 或匹配 tag |
| 次数循环 | `FOR(n).DO(a)` | n 为次数组件或表达式 |
| 条件循环 | `WHILE(x).DO(a)` | 可配 `BREAK` |
| 迭代循环 | `ITERATOR(it).DO(a)` | it 返回 `Iterator` |
| 异常处理 | `CATCH(a).DO(b)` | b 处理 a 的异常 |
| 重试 | `a.retry(3)` | 是小写后缀；没有 `RETRY(...).times(...)` |
| 超时 | `a.maxWaitSeconds(5)` | 也有 `maxWaitMilliseconds` |
| 前后置 | `PRE(a)` / `FINALLY(b)` | 配合主表达式使用 |
| 布尔组合 | `AND(a,b)` / `OR(a,b)` / `NOT(a)` | 用于条件表达式 |
| 节点修饰 | `.id(...)` / `.tag(...)` / `.data(json)` / `.bind(k,v)` | `data` 单参，KV 双参用 `bind` |
| 子变量 | `x = THEN(a,b); THEN(x,c);` | 无 `let`，赋值语句必须有分号 |

规则文件支持 `.xml`、`.json`、`.yml` 及 `.el.xml`、`.el.json`、`.el.yml`；没有纯 `.el` 文件格式。完整语法和约束读 `references/el-rules.md`。

`WHEN.any`、`must`、`percentage` 只是达到条件后让主流程提前继续。所有分支都可能已提交，`CompletableFuture.cancel(true)` 不能可靠停止底层任务；未等待分支仍可能继续写共享 Context 或产生外部副作用。

### 组件

| 行为 | 基类 / 方式 | 主方法 |
|---|---|---|
| 普通处理 | `NodeComponent` | `process()` |
| 布尔判断 | `NodeBooleanComponent` | `processBoolean()` |
| 多路选择 | `NodeSwitchComponent` | `processSwitch()` |
| 次数循环 | `NodeForComponent` | `processFor()` |
| 迭代数据 | `NodeIteratorComponent` | `processIterator()` |
| 声明式组件 | `@LiteflowComponent` + `@LiteflowMethod` | 可用 `@LiteflowCmpDefine` 声明节点类型 |

组件内用 `getRequestData()` 取流程入参，用 `getContextBean(...)` 取上下文。常用钩子：`isAccess`、`beforeProcess`、`afterProcess`、`onSuccess`、`onError`、`isContinueOnError`、`isEnd`、`rollback`。

组件通常是容器单例，Node 克隆仍共享组件实例；请求状态必须放 Context／Slot，不要放成员字段。

### 执行器

```java
LiteflowResponse response = flowExecutor.execute2Resp(
        "chain1", request,
        ExecuteOption.of()
                .requestId("req-001")
                .conversationId("conversation-001")
                .contextClass(OrderContext.class));

Future<LiteflowResponse> future = flowExecutor.execute2Future(
        "chain1", request, ExecuteOption.of()
                .autoConversationId()
                .contextClass(DefaultContext.class));

LiteflowResponse direct = flowExecutor.execute2RespWithEL(
        "THEN(a, b)", request, null, OrderContext.class);
```

- 新代码需要组合 requestId、conversationId、上下文或事件监听器时，优先 `ExecuteOption`。
- `ExecuteOption.contextClass(...)` 尝试为本次执行反射创建上下文，创建失败的项会被过滤，复杂构造对象应改传 Bean；`contextBean(...)` 直接复用已有实例，跨请求／并发隔离由调用方负责。
- 同一 `ExecuteOption` 同时设置 Class 与 Bean 时，Class 非空就优先，Bean 会被忽略。空 `ExecuteOption`／`null` option 不会自动补 `DefaultContext`，需要上下文时必须显式设置。
- `execute2RespWithEL` 没有 `(el, param, Context.class)` 三参重载；自定义上下文必须用四参形式，requestId 可传 `null`。
- 失败异常取 `response.getCause()`，不是 `getException()`。
- 常用结果：`isSuccess()`、`getContextBean(...)`、`getExecuteStepStrWithTime()`、`getExecuteSteps()`、`getRequestId()`、`getConversationId()`、`getTimeoutItems()`。

### 核心配置

Spring Boot 配置前缀为 `liteflow.*`：

| key | 默认值 | 说明 |
|---|---|---|
| `parse-mode` | `PARSE_ALL_ON_START` | 另有两种首次执行时解析模式 |
| `slot-size` | `1024` | 初始槽位数，可扩容 |
| `when-max-wait-time` / `-unit` | `15000` / `MILLISECONDS` | WHEN 整体等待时间 |
| `global-thread-pool-size` | `64` | Spring Boot 全局异步节点线程池；Solon 默认 `16` |
| `global-thread-pool-queue-size` | `512` | 全局异步队列容量 |
| `when-thread-pool-isolate` | `false` | 每个 WHEN 是否隔离线程池 |
| `support-multiple-type` | `false` | 混用多种规则文件格式，不代表可混用多个配置源 |
| `enable-monitor-file` | `false` | 本地规则文件监听 |
| `fast-load` | `false` | 快速解析 |
| `enable-virtual-thread` | `true` | 仅 JDK 21+ 生效 |
| `print-execution-log` | `true` | 执行过程日志 |
| `metrics.enabled` | `true` | 有 MeterRegistry 时启用 Micrometer 指标 |

`whenMaxWorkers` 和 `printExecutionResult` 不是有效的 LiteFlow 配置。完整表及 Spring、Solon、纯 Java 差异读 `references/config.md`。

### Rule-DB 与 Metrics

- Rule-DB 在 2.16.1 引入，2.16.2 当前仍有 SQL、PostgreSQL、MongoDB、Redis、ZooKeeper、etcd、Nacos 七个后端，classpath 七选一。
- Rule-DB 与 `rule-source` 互斥；外部存储是权威源，JVM 使用轻量索引和有界懒加载缓存；发布统一走 `RulePublisherFactory`。
- 传统 `liteflow-rule-*` 配置源与 `liteflow-rule-db-*` 是两套运行模型，迁移时不能同时保留同一后端插件。
- `liteflow-metrics` 提供 chain/node 次数、耗时、错误、在途指标及 `/actuator/liteflow` 结构端点；它与简单日志监控 `liteflow.monitor.*` 相互独立。

### LiteFlow Agent 2.16.2

- 引入 starter、`liteflow-agent-core` 和所选模型模块；继承 `HarnessAgentComponent`。完整可用示例读 [agent.md](references/agent.md)。
- 应用身份使用 `liteflow.agent.application-name`，Spring Boot 默认取 `spring.application.name`。会话由应用名、`conversationId` 和稳定的 `agentKey` 隔离；没有请求级 `userId` 维度，业务接口自行校验会话归属。
- 配置使用 `session-store.*`；JSON 默认持久化到 `./data/agent-state`，也支持 Redis／MySQL。三者独立于本地／Docker 执行环境。
- 文件工具默认可用，Shell 默认开启。纯聊天显式覆写 `enableShellTool()` 返回 `false`；本地 Shell 开启时必须配置 `harness.local.workspace-root`。
- `execution-timeout` 默认 `10m`，`max-iterations` 默认 `100`；等会话锁和首次构建不包含在该执行计时内。
- 流式输出需要模型 `.stream(true)` 和 `ExecuteOption.eventListener(...)`；正文事件为 `agent.text.delta`。同步方法仍等待最终结果。
- `invocation-guard.mode=AUTO` 根据存储选择本地或分布式协调；同一会话共享工作区，多个 Agent 放入 `WHEN` 也不保证同时运行。
- 聊天历史用 `AgentConversationService`；模型上下文压缩不会删展示历史。删除会话不会自动清除全部文件和快照。
- 默认权限为 BYPASS，人工确认必须显式配 ASK 和 `AgentConfirmationHandler`。`toolkit.parallel`、`skills.strict` 是当前不生效的配置，不能据此承诺行为。
- Docker 与三种存储自由组合；JSON 持久恢复需保存快照目录，Redis／MySQL 快照在后端保存，不能同时设置本地 `snapshot-root`。

## 知识地图

只加载当前问题需要的文件：

| 问题 | Reference |
|---|---|
| 框架定位、版本/JDK、模块、执行模型 | `references/overview.md` |
| 安装、Hello World、Spring Boot/Spring/Solon/纯 Java | `references/quickstart.md` |
| 配置全集及不同容器差异 | `references/config.md` |
| 组件类型、注册、声明式组件、组件钩子 | `references/components.md` |
| EL 全语法、修饰符、重试、继承、校验 | `references/el-rules.md` |
| 上下文、别名、参数注入、表达式取参 | `references/context.md` |
| FlowExecutor、ExecuteOption、LiteflowResponse | `references/executor.md` |
| 脚本语言、绑定变量、刷新、验证、卸载 | `references/scripts.md` |
| 传统规则配置源 | `references/rule-sources.md` |
| Rule-DB 七后端、发布、一致性、降级、存储协议 | `references/rule-db.md` |
| Micrometer、Prometheus、Actuator 端点 | `references/metrics.md` |
| 元数据操作与热刷新 | `references/metadata.md` |
| FlowExecutor、WHEN、虚拟线程等线程池 | `references/thread-pools.md` |
| 动态构造 Node、EL、Chain | `references/dynamic-build.md` |
| 决策路由与 `executeRouteChain` | `references/decision-routing.md` |
| 框架级生命周期 | `references/lifecycle.md` |
| 降级、回滚、切面、步骤、监控等高级能力 | `references/advanced.md` |
| 测试范式与源码示例索引 | `references/testing.md` |
| 性能、吞吐、启动速度调优 | `references/overview.md`、`references/config.md`、`references/thread-pools.md`、`references/advanced.md` |
| 非 Agent 跨版本升级、补丁选择 | `references/overview.md`、`references/faq-pitfalls.md` |
| Agent 快速开始、HarnessAgentComponent、多 Agent 编排、可靠性、离线测试 | `references/agent.md` |
| Agent 模型平台、Java/内置/MCP 工具、中间件、Skills | `references/agent-models-tools.md` |
| Agent 会话、Session 存储、聊天历史、事件、结构化输出、HITL、并发 | `references/agent-state-events-hitl.md` |
| Harness、压缩、记忆、沙箱、计划与子代理 | `references/agent-harness.md` |
| Agent 全部配置、默认值、约束和保留项 | `references/agent-config.md` |
| A2A 远程 Agent 客户端 | `references/agent-a2a.md` |
| 从旧 ReAct API 迁移到 2.16.2 | `references/react-agent.md` |
| 核心源码调用链和类索引 | `references/code-internals.md` |
| 常见报错与易错点 | `references/faq-pitfalls.md` |

## 作答要求

- 给出可直接采用的最小答案，再补充必要的边界、配置和排错信息；不要为了展示覆盖面而堆砌无关功能。
- 涉及版本、默认值、废弃 API、并发、资源所有权和安全边界时，必须读取对应 reference 或当前源码后再答。
- 用户给出旧 Agent 代码时，先指出它属于哪个版本，再给 2.16.2 的完整替代写法；不要混搭新旧模块。
- API 与配置示例默认描述 `2.16.2` 源码行为。用户指定其他版本时先核验该版本，不把开发中间态当作发布 API。
- 用法问题可注明对应 reference；源码问题必须引用实际文件和行号。源码发生移动时按类名重新定位，不要沿用 reference 中可能过期的绝对行号。

## 辅助脚本

`scripts/source-lookup.sh`：

| 子命令 | 作用 |
|---|---|
| `path` | 定位本地 LiteFlow 仓库，不克隆 |
| `explore <问题>` | 在存在 `.codegraph/` 时调用 CodeGraph 理解符号与调用链 |
| `grep <模式>` | 搜索 Java 源码 |
| `grepall <模式>` | 搜索仓库所有文本 |
| `find <名称>` | 按文件名定位 |
| `show <相对路径> [a-b]` | 带行号显示源码 |
| `clone` | 经用户同意后克隆指定版本到缓存，默认请求 `v2.16.2` |

环境变量：`LITEFLOW_REPO` 增加最高优先级的本地仓库候选，`LITEFLOW_TAG` 指定克隆分支或 tag，`LITEFLOW_CACHE` 指定缓存目录。

`scripts/version-check.sh` 每天缓存一次 Skill 版本检查；它只读取远端 `SKILL.md` 的 `metadata.version`，不会执行远端代码。

维护技能时使用 `scripts/audit-coverage.py --source <源码仓库> --homepage <官网仓库>` 复查覆盖清单、源码证据和 reference 定位。该结果衡量文档功能覆盖，不代表代码测试覆盖率或真实问答准确率。
