# 常见坑与 FAQ

> 本文件由本 skill 其它 reference（均源自 LiteFlow v2.16.X 官方文档 + 源码）汇总而成。每条都标注了出处文件，需细节请查对应 reference。**未在这些 reference 中出现、又无法在源码中确认的点，不要在此添加——避免臆造。**

---

## 一、高频 FAQ

**Q1：支持哪些 JDK / SpringBoot？**
JDK 8 ~ 25；SpringBoot 2.X / 3.X 用 `liteflow-spring-boot-starter`，SpringBoot 4.X 用 `liteflow-spring-boot4-starter`（需 JDK17+）；也支持 Spring、Solon、纯 Java。详见 `references/overview.md`、`references/quickstart.md`。

**Q2：规则写在哪？必须用规则文件吗？**
规则写在 `flow.xml`/`flow.json`/`flow.el` 等规则文件的 `<chain>` 中。也可：①代码动态构造（`references/dynamic-build.md`，此时 `rule-source` 失效）；②直接执行一段 EL 字符串（`execute2RespWithEL`，v2.15.0+，见 `references/executor.md`）。

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
支持 Groovy/JS/Python/QLExpress/Lua/Aviator/Kotlin/Java 等多语言（各自 Maven 坐标不同）。脚本节点类型有 script/switch_script/boolean_script/for_script 四种；**没有"迭代循环"脚本节点**，迭代场景用 `for_script`。详见 `references/scripts.md`。

---

## 二、易错点 / 坑（均经文档或源码核对）

### 执行器 / Response（`references/executor.md`）
- ❌ `response.getException()` → ✅ **`response.getCause()`**（方法名以源码为准）。
- ❌ `getExecuteStepInfoList()` 不存在 → ✅ `getExecuteSteps()`，且返回 **`Map<String, List<CmpStep>>`**（文档曾写作 `Map<String, CmpStep>`）。
- `LiteflowResponse` **没有顶层"总耗时" getter**；总耗时需自行遍历 `getExecuteStepQueue()` 累加 `CmpStep.getTimeSpent()`。
- `LiteflowResponse` 不宜直接序列化返回前端，应用层自建 DTO。
- **流程入参 ≠ 上下文**：把上下文实例当 `param` 传入，组件里从同类上下文读不到值；`param` 只能 `this.getRequestData()` 取。

### 配置（`references/config.md`）
- v2.16.X **不存在**这些配置名，勿臆造：`whenMaxWorkers`（并发由 `global-thread-pool-size` 控制）、`printExecutionResult`（应为 `print-execution-log`）。⚠️ 注意：`chain-cache.enabled` / `chain-cache.capacity` 是**真实存在**的配置（只是未写在官方 050 文档里），勿将其误当臆造而避开——详见 `references/config.md`。
- 改用"代码动态构造规则"后，`rule-source` **自动失效**（不必也不能再配规则文件）。
- 监控项在 SpringBoot 下是 `liteflow.monitor.*` 子节点；在 Spring XML / 纯代码下被**拍平**为 `enableLog/queueLimit/delay/period`。
- 纯代码场景类型为强类型：`setWhenMaxWaitTimeUnit(TimeUnit.MILLISECONDS)`、`setParseMode(ParseModeEnum.X)`、`setDelay/setPeriod(long)`。

### 组件（`references/components.md`）
- 选择组件 `processSwitch()` 返回的是**目标 nodeId**（字符串），不是下标。
- 声明式组件：用 `@LiteflowComponent("id")`（或 `@Component`）**注册 nodeId**，方法用 `@LiteflowMethod(...)` 映射；**节点类型**写在 `@LiteflowMethod(nodeType=...)`，或在类上加 `@LiteflowCmpDefine(类型)`（二者都有时以类上 `@LiteflowCmpDefine` 为准，见 `SpringDeclComponentParser`）。`@LiteflowCmpDefine` **只声明类型、不能注册 nodeId**。方法第一参数固定 `NodeComponent bindCmp`（多组件场景注意区分）。
- 组件用 `@LiteflowComponent("nodeId")` 注册，`nodeId` 需符合命名约束。

### EL（`references/el-rules.md`）
- 算子**大小写敏感**，统一大写（`THEN`/`WHEN`...）。
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
- 决策路由规则存储**仅支持 XML 文件与数据库**两种。

### 源码细节（`references/code-internals.md`）
- `ScriptIteratorComponent` 在 v2.16.X 源码中**未能确认存在**（脚本仅注册了 SCRIPT/SWITCH_SCRIPT/BOOLEAN_SCRIPT/FOR_SCRIPT 四类）——遇到"迭代脚本组件"类问题，请按决策流程走第 2/3 步实地查源码，勿臆测。
- `MaxWaitTimeOperator.java` 文件虽存在但**未在 QlExpressUtils 注册**，对外只暴露 `maxWaitSeconds`/`maxWaitMilliseconds`，没有 `maxWaitTime` 算子。
- `fastLoad=true` 会关闭 CopyOnWrite 集合（启动更快，但热刷新并发安全性下降），生产慎用。

### 生命周期（`references/lifecycle.md`）
- 区分**框架级生命周期接口**（启动/执行前后，本文件）与**组件级钩子**（`beforeProcess`/`afterProcess` 等，见 `components.md`）。
- 执行时钩子 `PostProcessChainExecuteLifeCycle` 在**主链 + 每个子链**都会触发（多次），`PostProcessFlowExecuteLifeCycle` 整次执行只触发一次。

---

## 三、当心"想当然"

如果你准备回答的内容**不在上述 reference 中、也不在源码里**，请回到 `SKILL.md` 的决策流程：先查 reference → 再查本地源码 → 仍不够则**请求用户同意后克隆源码**确认。**绝不凭记忆编造 API 或行为。**
