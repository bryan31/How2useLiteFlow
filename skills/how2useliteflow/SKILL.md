---
name: how2useliteflow
description: 当用户提到 LiteFlow（Java 轻量级规则引擎/业务编排框架）时启用。覆盖：组件、EL 规则（THEN/WHEN/IF/SWITCH/FOR/WHILE/ITERATOR 等）、上下文、脚本组件、规则配置源、Rule-DB 统一规则数据库（v2.16.1：SQL/PostgreSQL/MongoDB/Redis/ZooKeeper/etcd/Nacos 七后端、发布 API、多节点一致性）、指标监控（liteflow-metrics、Micrometer、Prometheus、/actuator/liteflow 端点）、配置项、执行器、AI Agent 编排（ReAct Agent / liteflow-react-agent）、测试与调试、源码细节。
metadata:
  version: "1.2.0"
---

# LiteFlow 助手

本 skill 帮助用户用 AI 使用 **LiteFlow（v2.16.1）**。它内置了从官方文档与源码蒸馏出的绝大部分**用法细节与代码细节**，并规定了“答不到时怎么办”的严格流程。

> 版本对齐：本 skill 内容对齐 LiteFlow **v2.16.1（tag `cac48e201`，2026-07-27，源码 `<revision>`=2.16.1）**，包含 **Rule-DB 七后端**与 **liteflow-metrics 指标模块**。源码仓库 HEAD 已为修复版 **2.16.1.1**（在 v2.16.1 之上多一个 javax-pro `ThreadLocal` 泄漏修复 #IK6XVN）；另有补丁版 **2.16.0.1**（修复 WHEN 并行子 chain 的 `ConcurrentModificationException` #IDB16L，该修复已含在 v2.16.1 内）。作答时涉及发布版与补丁版差异必须明确标注。

---

## 一、何时使用

用户提到以下任一场景时启用本 skill：
- 写**组件**（普通/选择/布尔/次数循环/迭代循环组件，或声明式组件）。
- 写 **EL 规则**（THEN/WHEN/IF/SWITCH/FOR/WHILE/ITERATOR/CATCH/RETRY/TIMEOUT/PRE/FINALLY/AND/OR/NOT、tag/data/bind 等）。
- **上下文**（数据上下文、别名、参数注入、表达式取参）。
- **脚本组件**（Groovy/JS/Python/QLExpress/Lua/Aviator/Kotlin/Java 等）。
- **规则配置源**（本地文件/SQL/ZK/Nacos/Etcd/Apollo/Redis/自定义）。
- **Rule-DB 统一规则数据库**（v2.16.1 新增：`liteflow-rule-db-sql/postgresql/mongodb/redis/zk/etcd/nacos` 七选一、统一发布 API、规则版本与多节点一致性、有界缓存与懒加载、`liteflow.rule-db.*` 配置、降级语义）。
- **指标监控**（v2.16.1 新增：`liteflow-metrics`、Micrometer 指标、Prometheus/Grafana 对接、`/actuator/liteflow` 结构端点）。
- **配置项**（SpringBoot/Spring/Solon/纯代码）。
- **执行器**（FlowExecutor 的执行方法、LiteflowResponse）。
- **编写 / 调试测试用例**（JUnit5 + SpringBoot 测试范式、`BaseTest` 全局状态清理、各功能的官方测试模块）。
- **AI Agent 编排**（`liteflow-react-agent`：把 ReAct Agent 当组件编排进 EL、模型/凭据配置、自定义工具、流式输出、会话/记忆）。
- **调试/报错/链路排查**、热刷新、线程池、动态构造、决策路由、生命周期、降级/回滚/切面等高级特性。
- 询问 **LiteFlow 源码实现/代码细节**（FlowExecutor、FlowBus、DataBus、Condition 树、两阶段解析等）。

---

## 二、回答 LiteFlow 问题时的决策流程（必须严格遵守）

> 这是最重要的章节。**绝不杜撰、绝不用网络内容充当 LiteFlow 行为依据。**

**先做更新自检**（每次会话首次触发本 skill 时）：必须先运行 `scripts/version-check.sh` 再处理用户问题；结果按「七、更新自检」一节处理，检查失败则静默继续，不得因该检查中断或拒绝正常回答。

**第 0 步 — 先查本文件速查表**（下方第三节）：约 80% 的常见问题（EL 算子、组件类型、执行 API、核心配置）可直接作答，无需加载任何文件。

**第 1 步 — 加载对应 reference**：速查表不够时，按"知识地图"（第四节）用 `Read` 打开 `references/<文件>.md`。绝大多数用法与代码细节问题在此解决。**作答时标注来源 reference 文件名**。

**第 2 步 — 本地源码**：若 reference 也未覆盖（通常是更冷门或更深层的源码细节），先探测本地 LiteFlow 仓库，按优先级：环境变量 `LITEFLOW_REPO` → `~/openSource/liteFlow`、`~/openSource/LiteFlow-Jdk17` 等常见布局 → `./liteFlow` → 克隆缓存。
- 用 `scripts/source-lookup.sh path` 探测（找到则打印绝对路径；找不到退出码 2）。
- 找到后用 `scripts/source-lookup.sh grep <关键词>`（搜 `*.java`）/ `grepall` / `find <名字>` / `show <相对路径> [a-b]` 定位，**引用 `path:line` 作答**。

**第 3 步 — 请求克隆（必须先征得用户同意）**：本地也没有、或问题明确需要线上/最新源码时，**停下来告知用户并请求确认**，例如：
> “这部分内容不在我的内置知识里。我可以 git clone LiteFlow 官方仓库（gitee.com/dromara/liteFlow，默认 `dev` 分支，与内置的 v2.16.1 开发源码对齐）到临时目录，从源码里确认后再回答。是否允许？”

- 用户**同意** → 运行 `scripts/source-lookup.sh clone`（克隆到缓存 `~/.cache/liteflow-skill`），再用 `grep/find/show` 定位，**引用 `path:line` 作答**。
- 用户**拒绝 / 未明确同意** → 如实说明"暂时无法确认，不建议臆测"，**不要**自行克隆、**不要**杜撰、**不要**用网络搜索结果充当 LiteFlow 的行为依据。

### 绝对禁止
- 在未读到对应 reference 或源码前，凭记忆编造 API、方法名、参数、配置项、默认值或行为。
- 把网络搜索（WebSearch/网页）结果当作 LiteFlow 真实行为的依据（除非用户明确要求联网查证）。
- 在用户未明确同意前执行 `git clone` 或 `source-lookup.sh clone`。

---

## 三、高频速查（直接作答，无需加载 reference）

> 以下均经官方文档 + 源码核对。下方若仍不够，去对应 reference 查细节。

### 3.1 EL 算子速查（详见 `references/el-rules.md`）

| 算子 | 语义 | 最小示例 |
|---|---|---|
| `THEN(a,b,c)`（别名 `SER`） | 串行 | `THEN(a, b, c)` |
| `WHEN(a,b,c)`（别名 `PAR`） | 并行（异步） | `WHEN(a, b, c)` |
| `IF(x, a, b)` | 条件（x 为布尔组件/表达式；可 `ELIF`/`ELSE`） | `IF(x, a, b)` |
| `SWITCH(x).to(a,b,c)` | 选择（x 返回目标 nodeId） | `SWITCH(x).to(a, b, c)` |
| `FOR(x).DO(y)` | 次数循环（x 返回次数） | `FOR(n).DO(a)` |
| `WHILE(x).DO(y)` | 条件循环 | `WHILE(x).DO(a)` |
| `ITERATOR(x).DO(y)` | 迭代循环（x 返回 Iterator） | `ITERATOR(it).DO(a)` |
| `BREAK(x)` | 循环中断（配合循环） | `WHILE(x).DO(a).BREAK(b)` |
| `CATCH(a).DO(b)` | 捕获 a 的异常交 b 处理 | `CATCH(a).DO(b)` |
| `.retry(n)`（小写、后缀形式） | 重试（v2.12.0+） | `THEN(a, b.retry(3))` 或 `THEN(a,b).retry(3)` |
| `a.maxWaitSeconds(5)` / `maxWaitMilliseconds(...)` | 超时控制 | `WHEN(a,b).maxWaitSeconds(5)` |
| `PRE(a,b)` / `FINALLY(a,b)` | 前置 / 后置（始终执行） | `THEN(PRE(a), b, FINALLY(c))` |
| `AND(a,b)` / `OR(a,b)` / `NOT(a)` | 布尔与/或/非（用于 IF 条件） | `IF(AND(a,b), c, d)` |
| 子变量赋值 | 复用片段（无 `let` 关键字，直接赋值；赋值语句必须以分号结尾） | `t1 = THEN(a, b); THEN(t1, c);` |
| 节点修饰 | `tag` / `data` / `bind` / `id` | `a.tag("t").bind("k","v")`（KV 双参用 `bind`；`data` 只收单参 JSON，如 `a.data("{\"k\":\"v\"}")`） |
| 链路继承 | `extends` | 见 el-rules.md |

**WHEN 并行修饰**：`ignoreError`（忽略错误继续）、`any`（任一完成即结束）、`must(a,b)`（必须完成的节点）、`percentage(n)`（按比例）、是否独立线程池等——细节见 el-rules.md。

**重试补充**：`.retry(n)` 可作用于组件/任意表达式/子变量/整个 chain；可追加指定异常全限定类名，如 `retry(3, "java.lang.NullPointerException")`（多个异常继续往后列，仅命中这些异常才重试）。没有 `RETRY(...)` 包装函数也没有 `.times()`，写成大写 `RETRY` 会解析失败。

**规则写在哪**：`flow.el.xml` / `flow.el.json` / `flow.el.yml`（经典格式 `flow.xml` / `flow.json` / `flow.yml`）等规则文件中 `<chain name="..."> ... </chain>`，结尾分号可省略；支持注释。注意没有纯 `.el` 后缀的规则文件写法（`flow.el` 启动会抛 `ErrorSupportPathException`）。

### 3.2 组件类型速查（详见 `references/components.md`）

| 想要的行为 | 用哪种组件 | 关键方法/注解 |
|---|---|---|
| 普通处理 | `NodeComponent` | `process()` |
| 多路选择（返回 nodeId） | `NodeSwitchComponent` | `processSwitch()` 返回字符串 |
| 布尔判断（IF/WHILE 条件） | `NodeBooleanComponent` | `processBoolean()` 返回 boolean |
| 次数循环 | `NodeForComponent` | `processFor()` 返回次数 |
| 迭代循环 | `NodeIteratorComponent` | `processIterator()` 返回 `Iterator` |
| 声明式（不继承基类） | `@LiteflowComponent("id")` 注册 Bean | 方法加 `@LiteflowMethod(PROCESS, nodeType=...)`；或类上加 `@LiteflowCmpDefine(类型)` 声明 nodeType |

- 注册：继承式/声明式组件都用 `@LiteflowComponent("nodeId")`（也可用 `name` 设别名）。
- **组件生命周期钩子**（继承式可覆写，声明式用 `@LiteflowMethod`）：`isAccess()`（准入，false 则跳过）、`beforeProcess()`/`afterProcess()`、`onSuccess()`/`onError()`、`isContinueOnError()`、`isEnd()`、`rollback()`。
- 组件内取上下文：`this.getContextBean(XxxContext.class)` / `this.getFirstContextBean()`；取流程入参：`this.getRequestData()`。

### 3.3 执行 API 速查（详见 `references/executor.md`）

```java
@Resource private FlowExecutor flowExecutor;

// 同步执行：chainId + 入参 + 多个上下文 Class（框架实例化）
LiteflowResponse resp = flowExecutor.execute2Resp("chain1", param, OrderContext.class, UserContext.class);

// 直接执行一段 EL（v2.15.0+，无需规则文件）；自定义上下文必须走带 requestId 的四参重载，requestId 可传 null（框架自动生成）
LiteflowResponse resp2 = flowExecutor.execute2RespWithEL("THEN(a, b, c)", param, null, OrderContext.class);

// 异步 / 路由
Future<LiteflowResponse> f = flowExecutor.execute2Future("chain1", param, OrderContext.class);
List<LiteflowResponse> rs = flowExecutor.executeRouteChain(param, OrderContext.class);
```

> ⚠️ `execute2RespWithEL` **没有** `(elStr, param, XxxContext.class)` 三参重载（源码仅 4 个重载，第三参是 `String requestId`，见 `FlowExecutor.java:302-341`；官方 050 文档示例照抄会编译报错）。自定义上下文必须走四参形式（`requestId` 可传 `null`）；无自定义上下文需求时用 `(elStr, param)` 两参形式即可（默认 `DefaultContext`）。

`LiteflowResponse` 常用取值（**方法名以源码为准**）：

| 需求 | 方法 |
|---|---|
| 是否成功 | `resp.isSuccess()` |
| 失败异常 | `resp.getCause()`（**是 `getCause`，不是 `getException`**） |
| 异常 code/message | `resp.getCode()` / `resp.getMessage()` |
| 上下文 | `resp.getContextBean(XxxContext.class)` / `getFirstContextBean()` |
| 步骤字符串（带耗时） | `resp.getExecuteStepStrWithTime()` |
| 结构化步骤 | `resp.getExecuteSteps()`（`Map<String, List<CmpStep>>`）/ `getExecuteStepQueue()` |
| 请求/会话/链路 ID | `getRequestId()` / `getConversationId()` / `getChainId()` |
| 超时节点（v2.12.3+） | `getTimeoutItems()` |
| 回滚步骤 | `getRollbackStepQueue()` / `getRollbackSteps()` |

### 3.4 核心配置速查（详见 `references/config.md`，SpringBoot `liteflow.*`）

| key | 默认 | 说明 |
|---|---|---|
| `rule-source` | — | 规则文件路径，**用规则文件时必填**；改为代码动态构造时自动失效 |
| `parse-mode` | `PARSE_ALL_ON_START` | 另有 `PARSE_ONE_ON_FIRST_EXEC` / `PARSE_ALL_ON_FIRST_EXEC`（懒加载） |
| `slot-size` | `1024` | 上下文槽位数，自动扩容 |
| `when-max-wait-time`(+`-unit`) | `15000`(ms) | WHEN 并行整体超时 |
| `global-thread-pool-size` | `64` | 全局异步节点并发上限 |
| `support-multiple-type` | `false` | 多种规则文件格式（xml/json/yml/el）混装时设 true；不能用它混装多个配置源（单源约束不变） |
| `enable-monitor-file` | `false` | 本地规则文件变更自动重载 |
| `fast-load` | `false` | 快速解析模式 |
| `enable-virtual-thread` | `true` | 仅 JDK21+ 生效 |
| `print-execution-log` | `true` | 执行过程日志 |
| `monitor.enable-log` | `false` | 简易监控统计 |

> ⚠️ 这些配置名在 v2.16.1 **无效**，勿臆造：`whenMaxWorkers`（Solon 插件 `LiteflowProperty.java:50` 中残留该字段，但不接入 `LiteflowConfig`，配置了没有任何效果；并发由 `global-thread-pool-size` 控制）、`printExecutionResult`（应为 `print-execution-log`）。`chain-cache.enabled` 与 `chain-cache.capacity` **真实存在**，仅在 Rule-DB 模式下不读取。

### 3.5 v2.16.1 新变化速览

| 新能力 | 一句话 | 详情 |
|---|---|---|
| **Rule-DB 统一规则数据库** | SQL/PostgreSQL/MongoDB/Redis/ZooKeeper/etcd/Nacos 七后端，classpath 七选一；存储为权威源 + JVM 有界缓存懒加载，多节点最终一致；与 `rule-source` **互斥**；统一发布 API `RulePublisherFactory` | `references/rule-db.md` |
| **liteflow-metrics 指标** | Micrometer 指标（chain/node 次数/耗时/错误/在途）+ `/actuator/liteflow` 结构端点；starter 已传递依赖；开关 `liteflow.metrics.enabled`（默认开），无 registry 无任何行为 | `references/metrics.md` |
| **节点执行生命周期钩子** | 新增框架级钩子 `PostProcessNodeExecuteLifeCycle`（before/after 节点执行，带耗时与异常；框架级钩子至此共 6 个） | `references/lifecycle.md` |
| **新异常 `ChainLoadException`** | Rule-DB 回源加载失败（规则存在但取不回来），区别于 `ChainNotFoundException` | `references/rule-db.md` §9 |

---

## 四、知识地图（问题类型 → reference 文件）

用 `Read` 打开 `references/` 下对应文件获取细节：

| 问题类型 / 关键词 | 加载文件 |
|---|---|
| 框架定位、执行模型、模块地图、版本/JDK 支持、性能 | `references/overview.md` |
| 安装运行、Hello World（SpringBoot/Spring/Solon/其他） | `references/quickstart.md` |
| 全部配置项、各场景差异、LiteflowConfig | `references/config.md` |
| 组件（继承式 5 种 / 声明式 / 生命周期钩子） | `references/components.md` |
| EL 全语法、组件参数语法、重试/超时/继承/验证 | `references/el-rules.md` |
| 数据上下文、别名、参数注入、表达式取参 | `references/context.md` |
| FlowExecutor 方法、入参、LiteflowResponse | `references/executor.md` |
| 测试用例与示例（测试范式、BaseTest 清理、功能→测试模块速查、DEMO） | `references/testing.md` |
| 脚本组件、各语言坐标、绑定变量、动态刷新/验证/卸载 | `references/scripts.md` |
| 规则配置源（本地/SQL/ZK/Nacos/Etcd/Apollo/Redis/自定义） | `references/rule-sources.md` |
| **Rule-DB 统一规则数据库**（v2.16.1：七后端上手、`rule-db.*` 配置、发布 API、一致性/降级/限制、手改存储规范） | `references/rule-db.md` |
| **指标监控**（v2.16.1：liteflow-metrics、Micrometer 指标目录、`/actuator/liteflow` 端点、PromQL、非 Spring 注册） | `references/metrics.md` |
| 元数据操作器、平滑热刷新、启动不检查 | `references/metadata.md` |
| 异步线程池（FlowExecutor 层/组件异步层/虚拟线程） | `references/thread-pools.md` |
| 动态构造 Node/EL/Chain | `references/dynamic-build.md` |
| 决策路由（概念/用法/executeRouteChain） | `references/decision-routing.md` |
| 框架级生命周期（启动时/执行时钩子接口） | `references/lifecycle.md` |
| 高级特性（降级/回滚/切面/隐式子流程/步骤/监控…18 项） | `references/advanced.md` |
| **AI Agent 编排**（ReAct Agent 组件、模型/凭据、自定义工具、流式输出、会话记忆、`liteflow-react-agent`） | `references/react-agent.md` |
| **源码细节**（FlowExecutor/FlowBus/DataBus/Condition 树/算子→类映射） | `references/code-internals.md` |
| 常见坑与 FAQ | `references/faq-pitfalls.md` |

---

## 五、引用规范

- **用法类问题**：作答末尾标注来源 reference 文件名，例如"详见 `references/el-rules.md`"。
- **代码/源码类问题**：引用源码 `path:line`（来自 `references/code-internals.md` 或第 2/3 步实地查到的源码）。
- 涉及版本依赖的 API/配置，标注所对齐版本（默认 v2.16.1 tag `cac48e201`；源码仓 HEAD 为修复版 2.16.1.1）。

## 六、关于 `scripts/source-lookup.sh`

本地优先 / 受控克隆 + 检索的命令行助手（POSIX sh，macOS 可直接运行）：

| 子命令 | 作用 |
|---|---|
| `path` | 打印解析到的本地仓库路径（找不到退出码 2，**不克隆**） |
| `clone` | **显式**克隆 gitee 仓库到缓存（默认 `dev` 分支，其 HEAD 与内置 `v2.16.1` tag 基线同源、仅多 2.16.1.1 的 javax-pro ThreadLocal 修复等少量提交；仅在用户同意后调用）。如需严格对齐内置基线，显式设置 `LITEFLOW_TAG=v2.16.1`；查 v2.16.1 新特性优先用本地源码或内置 `references/rule-db.md` / `references/metrics.md` |
| `grep <pattern>` | 在仓库 `*.java` 中检索（优先 `rg`，回落 `grep -rn`） |
| `grepall <pattern>` | 在仓库所有文件中检索 |
| `find <name>` | 按文件名查找 |
| `show <relpath> [a-b]` | 显示某文件（带行号，可选区间） |

环境变量：`LITEFLOW_REPO`（指定本地仓库覆盖探测）、`LITEFLOW_TAG`（可选，指定 tag/分支；不设则克隆 `dev`，显式留空 `LITEFLOW_TAG=` 才回落远端默认分支）、`LITEFLOW_CACHE`（默认 `~/.cache/liteflow-skill`）。

**职责边界**：脚本不做用户交互，是否克隆由本 skill 的决策流程（第 3 步）征得用户同意后决定。

---

## 七、更新自检

本 skill 每次会话首次被触发时，先运行 `scripts/version-check.sh` 检查自身是否为最新版本：

| 退出码 | 含义 | 处理方式 |
|---|---|---|
| 0 | 已是最新 | 继续正常工作，无需提示 |
| 2 | 远端有更新 | 告知用户本地与远端版本号，征得同意后执行脚本输出的 `npx skills update` 命令完成更新 |
| 1 | 检查失败（离线、网络受限等） | 静默跳过，不影响任何正常功能 |

该检查只读取远端 SKILL.md 的 `version` 字段，不执行远端任何代码。结果按天缓存在 `~/.cache/how2useliteflow/`（可用 `HOW2USELITEFLOW_CACHE` 覆盖），同一天内重复运行直接回放缓存、不重复联网；`HOW2USELITEFLOW_CHECK_FORCE=1` 可强制重新检查。

如需在 agent hook 中挂载本脚本，命令末尾必须追加 `|| true`——部分 hook 体系把退出码 2 解释为「阻断」，与本脚本的「有更新」含义冲突。
