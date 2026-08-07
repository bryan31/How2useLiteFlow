> 来源文档（相对 `04.v2.16.X文档/`）：
> - `090.🛩执行器/010.说明.md`
> - `090.🛩执行器/020.执行方法.md`
> - `090.🛩执行器/030.流程入参.md`
> - `090.🛩执行器/040.LiteflowResponse对象.md`
> - `090.🛩执行器/050.直接执行EL规则.md`
>
> 对齐版本：LiteFlow **v2.16.X**。下方方法签名除官方文档外，已用 `liteflow-core` 源码（`FlowExecutor.java` / `LiteflowResponse.java` / `CmpStep.java`）核对；与文档不一致处以源码为准并标注。

# 执行器 FlowExecutor

执行器（`com.yomahub.liteflow.core.FlowExecutor`）是一个流程的**触发点**，可在代码任意位置调用。在 Spring/SpringBoot 体系中，凡被 Spring 上下文管理的类，均可注入 `FlowExecutor` 使用。

```java
@Component
public class OrderService {
    @Resource
    private FlowExecutor flowExecutor;
}
```

## 执行方法总览

`FlowExecutor` 提供多组重载，按**返回类型**分为三类：返回 `LiteflowResponse`（同步）、返回 `Future<LiteflowResponse>`（异步）、返回 `List<LiteflowResponse>`（路由 chain）。下表签名以源码为准（`...` 表示可变参数）。

### 返回 `LiteflowResponse`（同步）

| 方法签名 | 说明 |
|---|---|
| `LiteflowResponse execute2Resp(String chainId)` | 上下文默认 `DefaultContext`，入参 `null` |
| `LiteflowResponse execute2Resp(String chainId, Object param)` | 上下文默认 `DefaultContext` |
| `LiteflowResponse execute2Resp(String chainId, Object param, Class<?>... contextBeanClazzArray)` | 按 **Class** 传入多个上下文（框架内部 new 出实例） |
| `LiteflowResponse execute2Resp(String chainId, Object param, Object... contextBeanArray)` | 按 **Bean 实例** 传入多个上下文 |
| `LiteflowResponse execute2RespWithRid(String chainId, Object param, String requestId, Class<?>... contextBeanClazzArray)` | 额外指定 `requestId`（Class 方式） |
| `LiteflowResponse execute2RespWithRid(String chainId, Object param, String requestId, Object... contextBeanArray)` | 额外指定 `requestId`（Bean 方式） |
| `LiteflowResponse execute2Resp(String chainId, Object param, ExecuteOption option)` | **源码新增**（以源码为准）：用 `ExecuteOption` 统一组合 `requestId` / `conversationId` / 上下文等，避免 overload 命名爆炸，新代码推荐入口 |
| `LiteflowResponse execute2RespWithEL(String elStr)` | 直接执行一段 EL，v2.15.0+；上下文默认 `DefaultContext`，入参 `null` |
| `LiteflowResponse execute2RespWithEL(String elStr, Object param)` | 同上，带初始入参 |
| `LiteflowResponse execute2RespWithEL(String elStr, Object param, String requestId, Class<?>... contextBeanClazzArray)` | 带 `requestId`，按 Class 传上下文 |
| `LiteflowResponse execute2RespWithEL(String elStr, Object param, String requestId, Object... contextBeanArray)` | 带 `requestId`，按 Bean 实例传上下文 |

> 文档（`020.执行方法.md`）只显式列出前两组 `execute2Resp`。其余重载（`WithRid` / `WithEL` / `ExecuteOption` 版本）来自源码核对，行为一致。

### 返回 `Future<LiteflowResponse>`（异步）

异步执行依赖 `FlowExecutor` 层面的线程池（详见官方"FlowExecutor 层面的线程池"章节）。源码核对的公开重载：

| 方法签名 |
|---|
| `Future<LiteflowResponse> execute2Future(String chainId, Object param, Class<?>... contextBeanClazzArray)` |
| `Future<LiteflowResponse> execute2Future(String chainId, Object param, Object... contextBeanArray)` |
| `Future<LiteflowResponse> execute2FutureWithRid(String chainId, Object param, String requestId, Class<?>... contextBeanClazzArray)` |
| `Future<LiteflowResponse> execute2FutureWithRid(String chainId, Object param, String requestId, Object... contextBeanArray)` |
| `Future<LiteflowResponse> execute2Future(String chainId, Object param, ExecuteOption option)` |

### 路由 chain（返回 `List<LiteflowResponse>`）

按 `namespace` 路由匹配后执行，返回多个 response。源码核对的公开重载：

| 方法签名 |
|---|
| `List<LiteflowResponse> executeRouteChain(Object param, Class<?>... contextBeanClazzArray)` |
| `List<LiteflowResponse> executeRouteChain(String namespace, Object param, Class<?>... contextBeanClazzArray)` |
| `List<LiteflowResponse> executeRouteChain(Object param, Object... contextBeanArray)` |
| `List<LiteflowResponse> executeRouteChain(String namespace, Object param, Object... contextBeanArray)` |
| `List<LiteflowResponse> executeRouteChainWithRid(Object param, String requestId, Class<?>... contextBeanClazzArray)` |
| `List<LiteflowResponse> executeRouteChainWithRid(String namespace, Object param, String requestId, Class<?>... contextBeanClazzArray)` |
| `List<LiteflowResponse> executeRouteChainWithRid(Object param, String requestId, Object... contextBeanArray)` |
| `List<LiteflowResponse> executeRouteChainWithRid(String namespace, Object param, String requestId, Object... contextBeanArray)` |

### 已废弃

- `@Deprecated DefaultContext execute(String chainId, Object param) throws Exception`：返回默认上下文，失败时直接抛异常。建议改用 `execute2Resp`。
- `@Deprecated void invoke(String nodeId, Integer slotIndex) throws Exception`：单独调用某个 node。

## 流程入参（param）

`execute2Resp` / `execute2RespWithEL` 的第二参数 `param` 是**流程初始入参**（如订单号、用户 ID 等），可以是任意对象，生产中常传入自封装的 Bean。

:::warning 重要区分
**流程入参** ≠ **上下文**。把一个上下文实例当 `param` 传入，并不等于组件里能从同类型上下文中读到值——它们是两个独立实例。流程入参**只能**在组件中通过 `this.getRequestData()` 取出。
:::

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        // 取出 FlowExecutor 第二个参数传入的对象
        OrderRequest requestBean = this.getRequestData();
    }
}
```

完整调用示例：

```java
// 入参为 OrderRequest；传入两个上下文 Class，框架会实例化
LiteflowResponse response = flowExecutor.execute2Resp(
        "chain1",
        orderRequest,
        OrderContext.class,
        UserContext.class
);
```

## 直接执行 EL 规则（不经规则文件）

支持版本：**v2.15.0+**。

简单表达式无需写入规则文件，可直接把 EL 字符串作为第一参数传入：

```java
// 自定义上下文必须走四参重载：第三参 requestId 传 null，由框架自动生成
LiteflowResponse response = flowExecutor.execute2RespWithEL(
        "THEN(a, b, c)",
        requestData,
        null,
        CustomContext.class
);
```

`execute2RespWithEL` 与 `execute2Resp` 用法一致，仅第一参数由 `chainId` 换成规则 EL。无自定义上下文需求时可直接用两参形式 `execute2RespWithEL(elStr, param)`（上下文默认 `DefaultContext`）。

:::warning 签名坑：三参形式不存在，照抄官方示例无法编译
官方文档（`050.直接执行EL规则.md`）示例写作 `execute2RespWithEL("THEN(a, b, c)", requestData, CustomContext.class)`，这个**三参签名在源码中不存在**。`execute2RespWithEL` 自引入（v2.15.0，commit `0da24f4b0`）起仅有 4 个公开重载（`FlowExecutor.java:302-341`）：`(String)`、`(String, Object)`、`(String, Object, String, Class<?>...)`、`(String, Object, String, Object...)`——第三参固定为 `String requestId`，传入 `XxxContext.class`（`Class` 类型）无任何重载可匹配，Java 重载解析无候选方法，**编译报错**。自定义上下文必须走带 `requestId` 的四参重载，`requestId` 传 `null` 即由框架自动生成。
:::

:::tip 实现机制
LiteFlow 不会每次请求都新建 chain。若多次请求的表达式 **MD5 指纹相同**，只会构建一次 chain 并由框架托管，开发者无需关心。
但若每次传入表达式都不同，会导致托管 chain 数量暴增——应避免，或结合"活跃规则保活策略"使用。
:::

## LiteflowResponse 对象

执行返回最多的就是 `LiteflowResponse`，封装了结果数据与过程数据。

:::warning 不适合序列化
该对象不适宜直接序列化返回前端/外部。应用层应自行构建 DTO 返回。
:::

### 是否成功 / 异常 / 编码

| Getter | 返回 | 说明 |
|---|---|---|
| `boolean isSuccess()` | `boolean` | 流程是否执行成功 |
| `Exception getCause()` | `Exception` | 失败时取异常对象（**注意方法名是 `getCause`，不是 `getException`**，以源码为准） |
| `String getMessage()` | `String` | 异常 message |
| `String getCode()` | `String` | 异常为 `LiteFlowException` 时返回其 `code`，否则 `null` |

`isSuccess() == false` 时必然存在异常：

```java
LiteflowResponse response = flowExecutor.execute2Resp("chain1", param, CustomContext.class);
if (!response.isSuccess()) {
    Exception e = response.getCause();
    String code = response.getCode();      // 可能为 null
    String msg = response.getMessage();
    log.error("流程失败 code={} msg={}", code, msg, e);
}
```

### 上下文数据

流程执行过程中读写上下文；返回数据应放在上下文里取出。

| Getter | 说明 |
|---|---|
| `<T> T getFirstContextBean()` | 只有一个上下文时的快捷取法 |
| `<T> T getContextBean(Class<T> contextBeanClazz)` | 按 Class 取上下文 |
| `<T> T getContextBean(String contextName)` | 按名称取上下文（源码核对存在） |
| `Slot getSlot()` | 取底层 `Slot`（一般不直接用） |

```java
// 单上下文
CustomContext ctx = response.getContextBean(CustomContext.class);
// 等价于：
// CustomContext ctx = response.getFirstContextBean();

// 多上下文
LiteflowResponse response = flowExecutor.execute2Resp("chain1", param, OrderContext.class, UserContext.class);
OrderContext orderCtx = response.getContextBean(OrderContext.class);
UserContext  userCtx  = response.getContextBean(UserContext.class);
```

### 执行步骤信息

| Getter | 返回 | 说明 |
|---|---|---|
| `Map<String, List<CmpStep>> getExecuteSteps()` | 按 nodeId 聚合的步骤（**注意：源码返回 `Map<String, List<CmpStep>>`**，文档写作 `Map<String, CmpStep>`，以源码为准） |
| `Queue<CmpStep> getExecuteStepQueue()` | 执行步骤队列（按执行顺序） |
| `String getExecuteStepStrWithTime()` | 带耗时的步骤字符串，如 `a[组件A]<201>==>b[组件B]<300>` |
| `String getExecuteStepStrWithoutTime()` | 不带耗时的步骤字符串 |
| `String getExecuteStepStr()` | 等价于 `getExecuteStepStrWithoutTime()` |
| `String getExecuteStepStrWithInstanceId()` | 带节点实例 ID 的步骤字符串（源码核对存在） |

步骤字符串格式：`组件ID[组件别名]<耗时毫秒>`，组件别名见官方"组件别名"章节。

:::tip 自动打印
每个流程执行结束后，框架会**自动打印**该步骤字符串，无需手动获取；如需持久化再自行调用。
:::

```java
LiteflowResponse response = flowExecutor.execute2Resp("chain1", param, CustomContext.class);

// 步骤字符串
String stepStr = response.getExecuteStepStrWithTime();
// 例：a[组件A]<201>==>b[组件B]<300>==>m[组件M]<1205>

// 结构化步骤
Map<String, List<CmpStep>> stepMap = response.getExecuteSteps();
Queue<CmpStep> stepQueue = response.getExecuteStepQueue();
```

### 关于"耗时 / cost"

`LiteflowResponse` **没有**顶层总耗时的 getter（以源码为准）。耗时信息分布在两处：

1. **单步耗时**：`CmpStep.getTimeSpent()`，单位毫秒；回滚耗时 `CmpStep.getRollbackTimeSpent()`。
2. **步骤字符串**：`getExecuteStepStrWithTime()` 已把每步耗时拼入。

如需流程总耗时，需自行遍历 `getExecuteStepQueue()` 累加 `getTimeSpent()`（以源码/官方文档为准）。

### 回滚步骤（源码核对存在）

| Getter | 返回 |
|---|---|
| `Queue<CmpStep> getRollbackStepQueue()` | 回滚步骤队列 |
| `Map<String, List<CmpStep>> getRollbackSteps()` | 按 nodeId 聚合的回滚步骤 |
| `String getRollbackStepStr()` | 回滚步骤字符串（等价于 withoutTime） |
| `String getRollbackStepStrWithTime()` | 带耗时的回滚字符串 |
| `String getRollbackStepStrWithoutTime()` | 不带耗时的回滚字符串 |

### 请求标识 / chain

| Getter | 返回 | 说明 |
|---|---|---|
| `String getRequestId()` | `String` | 本次执行请求 ID（未传则框架自动生成） |
| `String getConversationId()` | `String` | 会话 ID（源码核对存在，ReAct Agent 等连续对话场景使用） |
| `String getChainId()` | `String` | 本次执行的 chain ID |

### 超时对象

支持版本：**v2.12.3+**。

```java
List<String> timeoutNodeIds = response.getTimeoutItems();
```

`getTimeoutItems()` 返回执行中超时的对象（节点）ID 列表。

## 完整示例

```java
@Service
public class BizService {

    @Resource
    private FlowExecutor flowExecutor;

    public void run(String chainId, OrderRequest req) {
        // 1. 同步执行：入参 + 多上下文 Class
        LiteflowResponse response = flowExecutor.execute2Resp(
                chainId, req, OrderContext.class, UserContext.class);

        // 2. 判断成功
        if (!response.isSuccess()) {
            throw new RuntimeException("流程执行失败", response.getCause());
        }

        // 3. 取上下文结果
        OrderContext orderCtx = response.getContextBean(OrderContext.class);

        // 4. 取步骤与请求 ID（用于日志/追踪）
        String stepStr = response.getExecuteStepStrWithTime();
        String requestId = response.getRequestId();
        log.info("requestId={} steps={}", requestId, stepStr);
    }

    public void runEl(OrderRequest req) {
        // 直接执行一段 EL，无需规则文件（v2.15.0+）；requestId 传 null 由框架生成
        LiteflowResponse resp = flowExecutor.execute2RespWithEL(
                "THEN(a, b, c)", req, null, OrderContext.class);
        if (!resp.isSuccess()) {
            log.error("EL 执行失败", resp.getCause());
        }
    }

    public void runAsync(String chainId, OrderRequest req) {
        // 异步执行（依赖 FlowExecutor 线程池）
        Future<LiteflowResponse> future = flowExecutor.execute2Future(
                chainId, req, OrderContext.class);
        // ...后续通过 future.get() 取 LiteflowResponse
    }
}
```

## 取值速查表

| 需求 | 方法 |
|---|---|
| 是否成功 | `response.isSuccess()` |
| 失败异常 | `response.getCause()` |
| 异常 code / message | `response.getCode()` / `response.getMessage()` |
| 上下文 | `response.getContextBean(XxxContext.class)` / `getFirstContextBean()` |
| 步骤字符串（带耗时） | `response.getExecuteStepStrWithTime()` |
| 结构化步骤 | `response.getExecuteSteps()` / `getExecuteStepQueue()` |
| 单步耗时 | `cmpStep.getTimeSpent()`（毫秒） |
| 请求 ID / 会话 ID / chain ID | `getRequestId()` / `getConversationId()` / `getChainId()` |
| 超时节点 | `response.getTimeoutItems()`（v2.12.3+） |
| 组件内取流程入参 | `this.getRequestData()`（在 `NodeComponent` 中） |
