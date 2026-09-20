# 常见坑与 FAQ

> 本文件由本 skill 其它 reference（均源自 LiteFlow v2.16.X 官方文档 + 源码）汇总而成。每条都标注了出处文件，需细节请查对应 reference。**未在这些 reference 中出现、又无法在源码中确认的点，不要在此添加——避免臆造。**

---

## 一、高频 FAQ

**Q1：支持哪些 JDK / SpringBoot？**
JDK 8 ~ 25；SpringBoot 2.X / 3.X 用 `liteflow-spring-boot-starter`，SpringBoot 4.X 用 `liteflow-spring-boot4-starter`（需 JDK17+）；也支持 Spring、Solon、纯 Java。详见 `references/overview.md`、`references/quickstart.md`。

**Q2：规则写在哪？必须用规则文件吗？**
规则写在 `flow.xml`/`flow.json`/`flow.yml`（EL 后缀形式为 `flow.el.xml`/`flow.el.json`/`flow.el.yml`）等规则文件的 `<chain>` 中——**没有纯 `.el` 后缀**，`FlowParserProvider` 只认上述 6 种。也可：①代码动态构造（`references/dynamic-build.md`，可与 `rule-source` 已加载的规则共存）；②直接执行一段 EL 字符串（`execute2RespWithEL`，v2.15.0+，见 `references/executor.md`）。

**Q3：怎么热刷新规则？**
三种途径：①本地规则文件监听（`enable-monitor-file=true`）；②注册中心配置源（ZK/Nacos/Etcd/Apollo/Redis 等，变更自动推送）；③代码主动刷新（`LiteflowMetaOperator.reloadOneChain(...)` 等，见 `references/metadata.md`）。机制是"平滑热刷新"——旧流程不断、新流程接管。

**Q4：组件里怎么取上下文 / 取入参？**
取上下文：`this.getContextBean(XxxContext.class)` 或 `this.getFirstContextBean()`；取流程入参（`execute2Resp` 第二参数）：`this.getRequestData()`。**注意流程入参 ≠ 上下文**，详见 `references/context.md`、`references/executor.md`。

**Q5：怎么让某个组件跳过 / 终止整条链路？**
跳过本节点：覆写 `isAccess()` 返回 `false`；终止链路：覆写 `isEnd()` 返回 `true`。详见 `references/components.md`。

**Q6：怎么排查链路执行顺序与耗时？**
执行后框架会自动打印步骤字符串；也可 `resp.getExecuteStepStrWithTime()`（格式 `a[别名]<耗时ms>`）或结构化的 `getExecuteSteps()` / `getExecuteStepQueue()`。详见 `references/executor.md`、`references/advanced.md`（步骤信息）。

**Q7：WHEN 并行的超时和"是否独立线程池"怎么配？**
超时用 `WHEN(...).maxWaitSeconds(n)` 或全局 `when-max-wait-time`(+`-unit`)；每个 WHEN 是否独立线程池由 `when-thread-pool-isolate` 控制。并行修饰还有 `ignoreError`/`any`/`must`/`percentage`。详见 `references/el-rules.md`、`references/thread-pools.md`。

**Q8：脚本组件支持哪些语言？节点类型有几种？**
支持 Groovy/JS/Python/QLExpress/Lua/Aviator/Kotlin/Java 等多语言（各自 Maven 坐标不同）。脚本节点类型有 script/switch_script/boolean_script/for_script 四种；**没有“迭代循环”脚本节点**，`for_script` 只返回固定循环次数，不能代替迭代器。`ITERATOR` 必须使用 Java `NodeIteratorComponent`（或对应声明式 Java 组件）。详见 `references/scripts.md`。

**Q9：LiteFlow 支持事务吗？**
LiteFlow 与事务没有本质关系——它只是在本地把代码组件化、可编排化，**事务仍按原方式做**（官方《问答》）：在调用 `execute2Resp` 的外层方法加 `@Transactional`，任一组件异常导致失败时抛出异常即可触发本地事务回滚：

```java
@Transactional
public void runFlow() {
  LiteflowResponse response = flowExecutor.execute2Resp("chain1", 101);
  if (!response.isSuccess()){
    throw new IllegalStateException("LiteFlow 执行失败", response.getCause());
  }
}
```

`response.getCause()` 的类型是 `Exception`，直接 `throw response.getCause()` 只有在方法声明 `throws Exception` 或自行处理受检异常时才编译；业务代码通常包装成运行时异常。

上面的 Spring 线程绑定事务只覆盖**同步、同线程**执行的组件。`WHEN`、并行循环、`execute2Future` 等会切换线程，不会自动共享调用线程上的事务；这类场景应在各异步分支内单独建立事务，或使用适合的分布式事务／补偿方案。LiteFlow 的组件 `rollback()` 是失败后的业务补偿回调，不是数据库事务回滚。

**Q10：启动时报 `NoSuchMethodError` 是什么原因？**
大概率是 3 个传递依赖被本地其它 jar 传递依赖覆盖：`transmittable-thread-local`、`byte-buddy`、`hutool`（官方《问答》）。解法是在 `dependencyManagement` 中显式锁定为 LiteFlow 传递的版本——v2.16.1 源码 pom 实际传递版本为 hutool **5.8.39** / transmittable-thread-local **2.14.5** / byte-buddy **1.17.7**（官方问答给的最低要求为 ttl 2.12.3+ / byte-buddy 1.14.10+ / hutool 5.8.26+）。版本号随 LiteFlow 版本变化，以所对齐版本的源码 pom 为准。

**Q11：链路能跑一半暂停续跑 / 等第三方回调 / 编排多个服务吗？（无状态引擎边界）**
LiteFlow 是**单服务无状态**编排（官方《问答》）：①**不能**跑到一半手动停止后下次续跑——不存中间状态，业务应一次性跑完并自证幂等；有状态场景选 Flowable 等有状态引擎。②需等第三方回调时拆成**两段式**：第一段发出后自行持久化中间状态，回调回来再执行第二段。③**不支持跨服务分布式编排**——变通做法是独立出一个服务 X，在 X 内写组件包 RPC 调用远端 a/b/c，再用 EL 编排这些本地组件。

**Q12：报 `StackOverflowError`（栈溢出）怎么办？**
EL 解析本质是递归调用，链路嵌套层数很深时栈空间随之增长；JVM 线程栈 `-Xss` 太小就会栈溢出——调大 `-Xss` 即可（官方《问答》）。

---

## 二、易错点 / 坑（均经文档或源码核对）

### 执行器 / Response（`references/executor.md`）
- ❌ `response.getException()` → ✅ **`response.getCause()`**（方法名以源码为准）。
- ❌ `getExecuteStepInfoList()` 不存在 → ✅ `getExecuteSteps()`，且返回 **`Map<String, List<CmpStep>>`**（文档曾写作 `Map<String, CmpStep>`）。
- `LiteflowResponse` **没有顶层“总耗时” getter**；不要累加 `CmpStep.getTimeSpent()` 充当流程墙钟耗时，并行节点会造成重复累计。需要总耗时时在调用 `execute2Resp` 的外层计时，或使用 Metrics／链路追踪。
- `LiteflowResponse` 不宜直接序列化返回前端，应用层自建 DTO。
- **流程入参 ≠ 上下文**：把上下文实例当 `param` 传入，组件里从同类上下文读不到值；`param` 只能 `this.getRequestData()` 取。

### 配置（`references/config.md`）
- v2.16.X **不存在**这些配置名，勿臆造：`whenMaxWorkers`（并发由 `global-thread-pool-size` 控制）、`printExecutionResult`（应为 `print-execution-log`）。⚠️ 注意：`chain-cache.enabled` / `chain-cache.capacity` 是**真实存在**的配置（只是未写在官方 050 文档里），勿将其误当臆造而避开——详见 `references/config.md`。
- 代码动态构造与 `rule-source` 可以共存；只有 Rule-DB 模式与 `rule-source` 互斥。
- 监控项在 SpringBoot 下是 `liteflow.monitor.*` 子节点；在 Spring XML / 纯代码下被**拍平**为 `enableLog/queueLimit/delay/period`。
- 纯代码场景类型为强类型：`setWhenMaxWaitTimeUnit(TimeUnit.MILLISECONDS)`、`setParseMode(ParseModeEnum.X)`、`setDelay/setPeriod(long)`。

### 组件（`references/components.md`）
- 选择组件 `processSwitch()` 返回的是**目标 nodeId**（字符串），不是下标。
- 声明式组件：用 `@LiteflowComponent("id")`（或 `@Component`）**注册 nodeId**，方法用 `@LiteflowMethod(...)` 映射；**节点类型**写在 `@LiteflowMethod(nodeType=...)`，或在类上加 `@LiteflowCmpDefine(类型)`（二者都有时以类上 `@LiteflowCmpDefine` 为准，见 `SpringDeclComponentParser`）。`@LiteflowCmpDefine` **只声明类型、不能注册 nodeId**。方法第一参数固定 `NodeComponent bindCmp`（多组件场景注意区分）。
- 组件用 `@LiteflowComponent("nodeId")` 注册，`nodeId` 需符合命名约束。

### 上下文（`references/context.md`）
- **WHEN 并行分支并发读写同一上下文字段会产生数据竞争**：框架只保证 Slot/上下文实例在多请求间不串（上下文"本身"的线程安全），**上下文内字段的并发安全由用户自行保证**（官方《问答》、专题解释 01）——例如上下文里一个 `int` 被多个异步节点并发累加就会出错，应改用 `AtomicInteger`/并发容器，或避免共享可变状态。

### EL（`references/el-rules.md`）
- EL 主关键字（`THEN`/`WHEN`/`IF` 等）大写，方法式副关键字（`.tag`/`.data`/`.retry` 等）小写；`node`/`NODE` 与 `to`/`TO` 两种大小写均已注册，不能简单概括为“全部大写”。
- `maxWaitSeconds`/`maxWaitMilliseconds` 是**节点或编排上的修饰**，注意书写位置。
- `CATCH(a).DO(b)` 中 b 处理异常，**不要**让它再抛出而"吞掉"了原异常信息。
- 链路继承 `extends` 需要被继承的 chain 已定义（占位/解析顺序），注意循环依赖。

### 脚本（`references/scripts.md`）
- 各语言语法差异：Lua 用 `:` 调用；Aviator 用 `method(bean, args)`；Kotlin 用 `bindings`；Java(javax-pro) 类式且可用 `ContextAwareHolder` 取 Bean。
- 动态刷新脚本用 `LiteflowMetaOperator.reloadScript(...)`；卸载用 `FlowBus.unloadScriptNode(...)`。
- 多语言混合需各自引入对应脚本依赖。

### 动态构造（`references/dynamic-build.md`）
- `setChainName(...)` 已 `@Deprecated`，改用 `setChainId(...)`。

### 决策路由（`references/decision-routing.md`）
- `<route>` 里**只允许"与/或/非"表达式 + 布尔组件**，不能写其它编排。
- 决策路由规则存储：**文件类 XML/JSON/YAML + SQL 数据库**均支持；**传统 rule-source 插件源（ZK/Nacos/etcd/Apollo/Redis 等）不支持**；v2.16.1 Rule-DB 模式支持（`route_data` 列，见 `references/rule-db.md`）。

### 源码细节（`references/code-internals.md`）
- `ScriptIteratorComponent` 在 v2.16.X 源码中**未能确认存在**（脚本仅注册了 SCRIPT/SWITCH_SCRIPT/BOOLEAN_SCRIPT/FOR_SCRIPT 四类）——遇到"迭代脚本组件"类问题，请按决策流程走第 2/3 步实地查源码，勿臆测。
- `MaxWaitTimeOperator.java` 文件虽存在但**未在 QlExpressUtils 注册**，对外只暴露 `maxWaitSeconds`/`maxWaitMilliseconds`，没有 `maxWaitTime` 算子。
- `fastLoad=true` 会关闭 CopyOnWrite 集合（启动更快，但热刷新并发安全性下降），生产慎用。

### 生命周期（`references/lifecycle.md`）
- 区分**框架级生命周期接口**（启动/执行前后，本文件）与**组件级钩子**（`beforeProcess`/`afterProcess` 等，见 `components.md`）。
- 执行时钩子 `PostProcessChainExecuteLifeCycle` 在**主链 + 每个子链**都会触发（多次），`PostProcessFlowExecuteLifeCycle` 整次执行只触发一次（**非路由场景**；`executeRouteChain` 一次调用会对 N 个候选 chain 决策评估 + M 条命中 body 各触发一次，共 **N+M 次**，见 `references/lifecycle.md`）。

### Rule-DB 统一规则数据库（v2.16.1 新增，`references/rule-db.md`）
- `liteflow.rule-source` 与 `liteflow.rule-db.*` **互斥**：同时配置启动直接报错 `rule-source and rule-db mode cannot be used together, please remove one of them`，必须二选一。
- 七个 Rule-DB 插件（SQL/PostgreSQL/MongoDB/Redis/ZooKeeper/etcd/Nacos）**同一时刻 classpath 只能有一个**，多个共存启动报错；同一后端迁移时也应移除旧 `liteflow-rule-*` 插件。
- **Redis Cluster 必须配置 `liteflow.rule-db.redis.key-hash-tag`**：发布 Lua 触碰多个键，hash-tag 让它们落在同一 slot；cluster 模式缺失该配置会 fail-fast，单机／哨兵可省略。
- **MongoDB 必须是副本集或分片集群**，因为 Manifest 快照和发布都依赖事务；standalone 不支持。
- **Nacos Rule-DB 要求 Server 2.x+**，且一个应用的全部规则位于单个 Catalog，必须提前评估单配置容量；不要与客户端 1.4.4 的旧 `liteflow-rule-nacos` 同放 classpath。
- **手动改库必须 `version = version + 1`**：对账主判据是 version（其次是 `content_md5` 列存量值），只改内容不改 version → 改动**永不生效**。SQL 最小正确姿势：`UPDATE lf_chain SET el_data=..., version=version+1, content_md5=MD5(el_data) WHERE application_name=? AND chain_id=?`；想 3 秒内生效还要在同一事务补一条 change_log。
- **启动时存储不可用 = 启动失败**（manifest 拉取失败直接抛异常）；但运行期存储挂掉、缓存命中则照常执行（缓存是可用性下限）。
- 发布顺序：**先发脚本、再发引用它的 chain**，否则收敛窗口内别的节点拉到新 chain 找不到脚本，编译瞬时失败。
- Rule-DB 回源或编译失败时，有激活版本就继续使用 last-good；只有冷加载且没有任何可用版本时才抛 v2.16.1 新异常 **`ChainLoadException`**。它区别于规则不存在时的 `ChainNotFoundException`。
- Rule-DB 模式下 `parseMode`、`enableMonitorFile`、`chainCacheEnabled`/`chainCacheCapacity` **不再被读取**（解析时机、热重载、缓存语义均由 `rule-db.*` 接管），配了也没效果。

### Metrics 端点（v2.16.1，`references/metrics.md`）
- `/actuator/liteflow`、`/actuator/prometheus` 默认 **404**：必须 `management.endpoints.web.exposure.include=liteflow,prometheus`——**采集 ≠ 暴露**。
- 没引任何 Micrometer registry（如 `micrometer-registry-prometheus`）则**完全无指标行为**。

### 版本与构建边界

- 2.16.2 当前源码根 POM 使用 AgentScope 2.0.3，Agent 统一为 HarnessAgentComponent；旧开发分支示例需按 `react-agent.md` 迁移。
- Spring 6.1+ 参数化 Actuator 端点检查制品是否保留 `-parameters` 信息。
- 当前源码关闭 `liteflow.enable` 时同步关闭 `liteflow.metrics.enabled`；Metrics 装配没有 FlowExecutor Bean 前置条件，详见 `metrics.md`。
- javax-pro 脚本的 ThreadLocal 泄漏修复始于 2.16.1.1；升级时核对实际制品与源码，不能把“版本号更高”作为修复已包含的唯一证据。

## 三、当心"想当然"

如果你准备回答的内容**不在上述 reference 中、也不在源码里**，请回到 `SKILL.md` 的决策流程：先查 reference → 再查本地源码 → 仍不够则**请求用户同意后克隆源码**确认。**绝不凭记忆编造 API 或行为。**
