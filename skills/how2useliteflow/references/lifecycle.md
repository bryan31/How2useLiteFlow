> 来源文档（相对 `04.v2.16.X文档/`）：
> - `150.😸生命周期/010.启动时生命周期.md`
> - `150.🔍生命周期/020.执行时生命周期.md`
>
> 版本对齐：LiteFlow **v2.16.X**。全部接口名/方法名/参数类型已与 `liteflow-core` 源码
> （`com.yomahub.liteflow.lifecycle` 包，`@since 2.12.4`）核对一致。

# LiteFlow 框架级生命周期参考

LiteFlow 在**启动构造阶段**和**运行执行阶段**各提供了一组框架级生命周期接口。开发者实现这些接口、注册为 Spring/Solon Bean，即可在特定时机插入自定义逻辑（审计、埋点、链路/节点校验、脚本引擎定制等）。

所有接口都继承自标识接口 `com.yomahub.liteflow.lifecycle.LifeCycle`（空接口，仅作分类标识）。启动时框架通过 `LifeCycleHolder.addLifeCycle(...)` 把容器中所有 `LifeCycle` 实现按类型分别装入对应 List，运行期再逐个回调。

> ⚠️ **本文聚焦"框架级"生命周期**——由 `FlowExecutor` / `Chain` / `Node` / 脚本引擎这些**框架对象**的构造与执行触发，钩子粒度是"整条流程 / 整个节点 / 整个引擎"。
>
> 它**不是**组件内部的 `beforeProcess` / `afterProcess` / `beforeChainInvoke` 等方法——那些属于**组件级生命周期钩子**，定义在 `NodeComponent` 等组件基类内部，钩子粒度是"某个组件实例的一次执行"，可拿到 `RequestData`、`Slot`、当前 `Node` 等。组件级钩子请见 [components.md](./components.md)，不要混淆。

---

## 一、注册方式（通用）

1. 一个 Bean 实现下文一个接口。`LifeCycleHolder.addLifeCycle(...)` 使用 `if / else-if` 分类；同一类同时实现多个生命周期接口时只会注册首个匹配类型，不能可靠获得全部回调。
2. 在 Spring Boot 中加 `@Component`；在 Solon 中按对应方式注册为 Bean。
3. 无需额外配置——框架启动时会自动扫描 `LifeCycle` 实现。

> **同一接口多实现不会覆盖：**对同一生命周期接口声明多个 Bean，**不会互相覆盖**，框架会把它们放入 List 逐个回调。但 LiteFlow 不声明跨 Spring／Solon／手动注册方式的稳定顺序，不要让多个实现依赖彼此的先后；必须排序时合并成一个有明确内部顺序的实现。

---

## 二、启动时生命周期（构造阶段）

发生在框架解析规则、构造 `Chain` / `Node` / 初始化脚本引擎期间。触发次数跟对象构建和引擎初始化次数一致：启动解析、热更新、动态重建都可能再次触发，不能按“应用生命周期只执行一次”设计。

### 1. `PostProcessChainBuildLifeCycle` —— Chain 构造前后

每个 `Chain` 被构造时触发一次。可在此校验链路合法性、记录链路元信息、做权限过滤等。

```java
import com.yomahub.liteflow.lifecycle.PostProcessChainBuildLifeCycle;
import com.yomahub.liteflow.flow.element.Chain;
import org.springframework.stereotype.Component;

@Component
public class MyChainBuildLifeCycle implements PostProcessChainBuildLifeCycle {

    @Override
    public void postProcessBeforeChainBuild(Chain chain) {
        // Chain 对象构造之前：此时 chain 已含 id，但内部编排元素尚未完全组装
        System.out.println("即将构造 Chain: " + chain.getId());
    }

    @Override
    public void postProcessAfterChainBuild(Chain chain) {
        // Chain 对象构造完成：可拿到完整编排结构，做校验/缓存/上报
        System.out.println("Chain 构造完成: " + chain.getId());
    }
}
```

### 2. `PostProcessNodeBuildLifeCycle` —— Node 构造前后

每个节点（组件）被构造为 `Node` 对象时触发一次。可用于统计节点信息、做节点级权限校验。

```java
import com.yomahub.liteflow.lifecycle.PostProcessNodeBuildLifeCycle;
import com.yomahub.liteflow.flow.element.Node;
import org.springframework.stereotype.Component;

@Component
public class MyNodeBuildLifeCycle implements PostProcessNodeBuildLifeCycle {

    @Override
    public void postProcessBeforeNodeBuild(Node node) {
        // 节点构造前
        System.out.println("即将构造 Node: " + node.getId());
    }

    @Override
    public void postProcessAfterNodeBuild(Node node) {
        // 节点构造后：可读取 node 的类型、关联组件等信息
        System.out.println("Node 构造完成: " + node.getId());
    }
}
```

### 3. `PostProcessScriptEngineInitLifeCycle` —— 脚本引擎初始化后

仅当引入了脚本插件时才会触发，且每种脚本语言各触发一次。可用于向引擎注入全局变量、定制引擎行为。

```java
import com.yomahub.liteflow.lifecycle.PostProcessScriptEngineInitLifeCycle;
import org.springframework.stereotype.Component;

@Component
public class MyScriptInitLifeCycle implements PostProcessScriptEngineInitLifeCycle {

    @Override
    public void postProcessAfterScriptEngineInit(Object engine) {
        // engine 的真实类型随脚本语言而变，使用前需强转（见下表）
        if (engine == null) {
            System.out.println("该脚本语言无独立引擎对象");
            return;
        }
        System.out.println("脚本引擎初始化完成: " + engine.getClass().getName());
    }
}
```

**`engine` 参数的实际类型（按脚本语言）：**

| 脚本语言 | `engine` 实际类型 |
|---|---|
| Groovy / Aviator / JS(JDK) / Kotlin / Lua | `javax.script.ScriptEngine`（均为 JSR-223 实现） |
| JS(GraalJs) | `org.graalvm.polyglot.Engine` |
| Python | `org.python.util.PythonInterpreter` |
| QLExpress | `com.alibaba.qlexpress4.Express4Runner` |
| Java(Janino) / Java(Liquor) | `null`（通过静态类执行，无独立引擎对象） |

> 对 `null` 情况务必判空；对其它类型用 `instanceof` 判别后再强转，避免 `ClassCastException`。

---

## 三、执行时生命周期（运行阶段）

发生在 `FlowExecutor`、`Chain` 和 `Node`（组件）实际执行规则期间，通常按每次执行触发；钩子自身抛错时能否继续到达后续回调，以各调用点的异常边界为准。

### 1. `PostProcessFlowExecuteLifeCycle` —— FlowExecutor 执行前后

每调用一次 `FlowExecutor.execute2xxx(...)` 触发一次。粒度是**整次流程调用**（无论内部嵌套多少子链路，只触发 1 次）——此"1 次"结论**仅 `execute2xxx` 场景成立**；`executeRouteChain` 路由场景会放大为 N+M 组（见下文 [§三.4](#4-决策路由场景下的触发次数executeroutechain)）。适合做整次请求的链路追踪起止、耗时统计、入参/出参审计。

```java
import com.yomahub.liteflow.lifecycle.PostProcessFlowExecuteLifeCycle;
import com.yomahub.liteflow.slot.Slot;
import org.springframework.stereotype.Component;

@Component
public class MyFlowExecuteLifeCycle implements PostProcessFlowExecuteLifeCycle {

    @Override
    public void postProcessBeforeFlowExecute(String chainId, Slot slot) {
        // 此时 Slot 和上下文已分配，但 requestId、conversationId、param 尚未写入
        System.out.println("[Flow 前] chainId=" + chainId);
    }

    @Override
    public void postProcessAfterFlowExecute(String chainId, Slot slot) {
        // 流程执行后：可读取响应、异常、执行步骤、耗时等
        Exception ex = slot.getException();
        System.out.println("[Flow 后] chainId=" + chainId
                + ", 是否异常=" + (ex != null)
                + ", 步骤=" + slot.getExecuteStepStr(true));
    }
}
```

`postProcessBeforeFlowExecute` 的调用点早于 `slot.putRequestId(...)` 和 `slot.setChainReqData(...)`，因此这里读取 requestId／conversationId／流程入参通常为空。需要这些数据时放到 after 钩子、组件／Chain 钩子，或从调用层自行传给追踪设施。该 before 调用还位于 FlowExecutor 的主 `try/finally` 之外；若它向外抛异常，本次 Slot 和事件监听器可能来不及释放，因此实现必须在自身边界捕获异常。

### 2. `PostProcessChainExecuteLifeCycle` —— Chain 执行前后

每执行一个 `Chain` 触发一次。**与 FlowExecutor 生命周期的关键区别**：若一条主链路内嵌套了子链路，则 Chain 生命周期会被触发**多次**——主链和每个子链各一次。

```java
import com.yomahub.liteflow.lifecycle.PostProcessChainExecuteLifeCycle;
import com.yomahub.liteflow.slot.Slot;
import org.springframework.stereotype.Component;

@Component
public class MyChainExecuteLifeCycle implements PostProcessChainExecuteLifeCycle {

    @Override
    public void postProcessBeforeChainExecute(String chainId, Slot slot) {
        System.out.println("[Chain 前] " + chainId);
    }

    @Override
    public void postProcessAfterChainExecute(String chainId, Slot slot) {
        System.out.println("[Chain 后] " + chainId
                + ", 子链异常=" + slot.getSubException(chainId));
    }
}
```

**举例说明触发次数差异。** 对如下规则：

```xml
<chain id="mainChain">
    THEN(a, b, subChain);
</chain>

<chain id="subChain">
    WHEN(c, d);
</chain>
```

每执行一次 `mainChain`：
- `PostProcessFlowExecuteLifeCycle`：触发 **1 次**（仅 `mainChain`）；
- `PostProcessChainExecuteLifeCycle`：触发 **2 次**——`mainChain` 执行前后各一组、`subChain` 执行前后各一组。

### 3. `PostProcessNodeExecuteLifeCycle` —— Node（组件）执行前后（v2.16.1 新增）

每个组件正常推进到对应调用点时会触发一组，是框架级生命周期中粒度最细的钩子——入参直接是 `NodeComponent` 本身（可拿 `getNodeId()`、`getType()`、`getRefNode()` 等），after 方法还带回耗时与异常。适合做节点级耗时统计、指标采集、执行审计。

```java
import com.yomahub.liteflow.core.NodeComponent;
import com.yomahub.liteflow.lifecycle.PostProcessNodeExecuteLifeCycle;
import org.springframework.stereotype.Component;

@Component
public class MyNodeExecuteLifeCycle implements PostProcessNodeExecuteLifeCycle {

    @Override
    public void postProcessBeforeNodeExecute(NodeComponent cmp) {
        // 组件主逻辑执行前（先于组件级 beforeProcess）
        System.out.println("[Node 前] " + cmp.getNodeId());
    }

    @Override
    public void postProcessAfterNodeExecute(NodeComponent cmp, long timeSpent, Exception e) {
        // 组件级 afterProcess 正常返回后，在 finally 的后续位置触发
        // timeSpent 为本次执行耗时（毫秒）；e 为执行异常，成功时为 null
        System.out.println("[Node 后] " + cmp.getNodeId()
                + ", 耗时=" + timeSpent + "ms, 异常=" + (e != null));
    }
}
```

- **调用点**（源码 `liteflow-core/.../core/NodeComponent.java` 的 `execute()`）：before 钩子在主逻辑执行前统一回调（`:119-127`，回调语句在 `:122`）；生命周期 after 位于 `finally` 的后半段（`:184-188`，回调语句在 `:187`）。业务处理成功或抛错本身都不会跳过它，但前面的组件级 `self.afterProcess()` 若再次抛错，控制流到不了生命周期 after，因而不能承诺任何异常下都必然触发。
- **before 与 after 的异常策略不同**：Node before 钩子异常会被捕获并记录，不中断节点，但当前 `forEach` 会立即停止，排在后面的 before 实现不会被调用。Node after 钩子没有保护；任一实现抛错都会停止后续 after 回调，并从 `finally` 传播，甚至覆盖原业务异常。所有实现都应自行 `try/catch`，尤其不能从 after 向外抛。
- **注册方式**：与其他生命周期相同——Spring/Solon 下声明为 Bean 即可被自动扫描；`LifeCycleHolder` 为其设有独立列表与分发分支（`liteflow-core/.../lifecycle/LifeCycleHolder.java:25`、`:39-41`，getter 在 `:64-66`）。非 Spring 场景用 `LifeCycleHolder.addLifeCycle(...)` 手动注册。
- **典型实现**：liteflow-metrics 模块的 `NodeMetricsLifeCycle`（`liteflow-metrics/.../metrics/NodeMetricsLifeCycle.java:30`）就是基于它采集 node 级指标（执行次数/耗时/在途/错误），详见 [metrics.md](./metrics.md)。

### 4. 决策路由场景下的触发次数（`executeRouteChain`）

调用 `FlowExecutor.executeRouteChain(...)`（决策路由入口）时，钩子触发次数与 `execute2xxx` 不同，存在**放大效应**。一次路由调用内部：先对命名空间下**所有 N 个候选 route chain** 各做一次决策评估，再对**命中的 M 条 chain** 各执行一次 body——决策评估与 body 执行是各自独立的一次 `doExecute` 调用（`executeRouteChain` → `executeWithRoute` → `doExecuteWithRoute`，源码 `liteflow-core/.../core/FlowExecutor.java:536-537`、`:695`）：对每个候选 chain 调一次 `doExecute(..., ROUTE)`（`:727-728`）、对每条命中 chain 调一次 `doExecute(..., BODY)`（`:764-765`），共 N+M 次 `doExecute`。

而 `PostProcessFlowExecuteLifeCycle` 的 before/after 钩子就内嵌在 `doExecute` 中（before `:580-584` 在 ROUTE/BODY 模式分派 `:618-621` 之前、after `:666-669` 在分派之后），故三类执行时钩子在路由场景下的触发次数为：

| 钩子 | 路由场景触发组数 | 说明 |
|---|---|---|
| `PostProcessFlowExecuteLifeCycle` | **N + M 组** | 每次 `doExecute` 都触发；N 次决策评估 + M 次 body 执行各一组 |
| `PostProcessChainExecuteLifeCycle` | **M 组** | 仅 body 执行走 `Chain.execute()`（`Chain.java:147-176`，触发链钩子）；决策评估走 `Chain.executeRoute()`（`Chain.java:182-202`）**不含链钩子**，故不触发 |
| `PostProcessNodeExecuteLifeCycle` | 决策布尔组件 + body 内节点，逐个触发 | 决策评估执行的路由布尔组件同样是 `Node`，按 §三.3 规则每个都触发一组 |

> **路由场景下“整次流程只触发 1 次”不成立：**`executeRouteChain` 单次调用会使 `PostProcessFlowExecuteLifeCycle` 触发 **N+M 组**而非 1 组。做链路追踪／指标采集时，务必按 `chainId` 去重或显式感知该放大效应，避免重复计数。决策评估阶段（ROUTE）虽不触发链级钩子，但其 Flow 级钩子仍会触发。

> **生命周期实现必须自行兜底：**除 Node before 的专门保护外，Flow／Chain／构建／脚本初始化以及 Node after 等钩子大多没有统一异常隔离。before 抛错可能直接阻断执行或构建，`finally` 中的 after 抛错还可能覆盖原异常。监控、审计和清理类实现应在自身边界捕获异常，并避免阻塞、递归调用 LiteFlow 或修改共享结构。

---

## 四、从 `Slot` 能拿到什么

执行时前两类钩子（Flow / Chain）的入参都是 `(String chainId, Slot slot)`（Node 钩子入参为 `NodeComponent`，见上节）。`Slot` 是 LiteFlow 运行期的"数据总线"，几乎承载了本次执行的所有元信息。常用方法（源码：`com.yomahub.liteflow.slot.Slot`）：

| 方法 | 含义 |
|---|---|
| `getRequestId()` / `getConversationId()` | 请求标识 / 会话标识（多 agent 共享上下文场景） |
| `getChainId()` | 当前 Chain id |
| `getContextBean(Class)` / `getContextBean(key)` / `getFirstContextBean()` | 取出业务上下文 Bean（强类型） |
| `getResponseData()` / `setResponseData(T)` | 响应数据 |
| `getException()` / `getSubException(chainId)` | 主链异常 / 指定子链异常 |
| `getExecuteSteps()` / `getExecuteStepStr(boolean withTime)` | 执行步骤（`CmpStep` 集合）/ 带耗时的步骤串 |
| `getRollbackSteps()` / `getRollbackStepStr(boolean)` | 回滚步骤信息 |
| `getInput(nodeId)` / `getOutput(nodeId)` | 指定节点的输入/输出 |
| `getSwitchResult(key)` / `getIfResult(key)` 等 | 各类编排关键字（SWITCH/IF/FOR/WHILE/ITERATOR/BREAK/AND/OR/NOT）的中间判定结果 |
| `getPrivateDeliveryData(nodeId)` | 节点间隐式传递的数据 |
| `getTimeoutItemList()` | 发生超时的执行项列表 |
| `getAttachment(key)` / `setAttachment(key, value)` | 通用挂载点，存放自定义附带数据 |

> **提示：**`Slot` 的元信息是审计／追踪／故障定位的核心抓手。配合 `PostProcessFlowExecuteLifeCycle` 的“前后各一次”特性，可在 `postProcessAfterFlowExecute` 里一次性 dump 整条链路的步骤、耗时与异常，做全链路日志归档。

---

## 五、接口速查表

| 接口 | 阶段 | 触发时机 | 方法 | 可拿到的关键对象 |
|---|---|---|---|---|
| `PostProcessChainBuildLifeCycle` | 构建 | 每次 `Chain` 构造前后 | `postProcessBeforeChainBuild(Chain)` / `postProcessAfterChainBuild(Chain)` | `Chain`（id、编排结构） |
| `PostProcessNodeBuildLifeCycle` | 构建 | 每次 `Node` 构造前后 | `postProcessBeforeNodeBuild(Node)` / `postProcessAfterNodeBuild(Node)` | `Node`（id、类型、关联组件） |
| `PostProcessScriptEngineInitLifeCycle` | 初始化 | 每次相应脚本引擎初始化后（需引入脚本插件） | `postProcessAfterScriptEngineInit(Object engine)` | 脚本引擎对象（类型随语言变，可能为 `null`） |
| `PostProcessFlowExecuteLifeCycle` | 执行 | 每次 `FlowExecutor` 调用前后各 1 次（整次流程仅 1 组；决策路由 `executeRouteChain` 为 N+M 组，见 §三.4） | `postProcessBeforeFlowExecute(String, Slot)` / `postProcessAfterFlowExecute(String, Slot)` | `chainId` + 完整 `Slot`（请求/响应/步骤/异常/上下文） |
| `PostProcessChainExecuteLifeCycle` | 执行 | 每个 `Chain` 执行前后各 1 次（含子链，主链+子链各 1 组） | `postProcessBeforeChainExecute(String, Slot)` / `postProcessAfterChainExecute(String, Slot)` | `chainId` + 当前 `Slot`（含子链异常等） |
| `PostProcessNodeExecuteLifeCycle`（v2.16.1 新增） | 执行 | 每个组件执行前后各 1 组（每次执行都触发，after 在 `finally` 中） | `postProcessBeforeNodeExecute(NodeComponent)` / `postProcessAfterNodeExecute(NodeComponent, long, Exception)` | `NodeComponent`（nodeId、type、refNode）+ 耗时 `timeSpent` + 异常 `e` |

---

## 六、与"组件级生命周期钩子"的边界

| 维度 | 框架级生命周期（本文） | 组件级生命周期钩子（见 [components.md](./components.md)） |
|---|---|---|
| 定义位置 | `com.yomahub.liteflow.lifecycle.*` 接口 | 组件基类（如 `NodeComponent`）内部方法 |
| 粒度 | 整条流程 / 整个 Chain / 每个 Node 的构造与执行 / 整个引擎 | 单个组件实例的一次执行 |
| 典型方法 | `postProcessAfterFlowExecute`、`postProcessAfterChainBuild` | `beforeProcess`、`afterProcess`、`beforeChainInvoke` 等 |
| 能否注入业务上下文 | 通过 `Slot` 间接获取 | 直接在组件内拿 `getContextBean(...)`、`getSlot()` |
| 适用场景 | 全局审计、链路追踪、构造期校验、引擎定制 | 单组件的前置准备、后置清理、节点级埋点 |

**判断准则**：要"对每条链路/每个节点/每次引擎做点什么" → 框架级生命周期；要"在某个具体组件跑之前/之后做点什么" → 组件级钩子。两者可同时使用，互不冲突。
