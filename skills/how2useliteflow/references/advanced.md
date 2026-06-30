> 来源：liteflow-homepage/docs/04.v2.16.X文档/160.🎨高级特性/（031~190 全部 18 篇）。本文档对齐 LiteFlow **v2.16.X**，所有类名/注解/配置 key 均已与 `liteFlow` 源码交叉核对。版本要求以各节标注的 `<Badge>` 为准；未写明版本即表示在 v2.16.X 已可用。

# LiteFlow 高级特性合集

本文收录 v2.16.X 的高级特性。每个特性给出：一句话作用、关键 API/注解/配置、最小可运行示例。特性之间相互独立，可按需查阅。

---

## 本地规则文件监听

让 `rule-source` 指向的本地磁盘规则文件被修改后，框架自动热刷新整个规则，无需手动调用刷新接口。

- 关键配置：`liteflow.enable-monitor-file=true`（默认 `false`）
- `rule-source` 既可指向类路径内文件，也可指向本地磁盘绝对路径；支持 `**` 模糊匹配，匹配到的所有文件都会被监听（v2.11.1+）

```properties
# 单文件
liteflow.rule-source=/Users/xxx/liteflow/test/flow.xml
# 模糊匹配（v2.11.1+，所有匹配文件均被监听）
liteflow.rule-source=/Users/xxx/liteflow/**/flow*.xml
# 开启监听
liteflow.enable-monitor-file=true
```

---

## 组件降级

当规则里编排了一个**不存在**的组件时，运行时自动路由到指定的“降级组件”代替执行，从而避免启动/运行报错。版本：v2.11.1+。

- 开关配置：`liteflow.fallback-cmp-enable=true`（默认关闭）
- 声明降级组件：在组件类上加 `@FallbackCmp` 注解（标注于普通/布尔/次数循环等各类型组件均可，每种类型目前只允许定义**一个**降级组件）
- 触发条件：规则中必须用 `node("xxx")` 关键字包裹可能缺失的组件 id；不加 `node` 不会路由到降级组件

```properties
liteflow.fallback-cmp-enable=true
```

```java
// 普通组件的降级组件 E
@LiteflowComponent("E")
@FallbackCmp
public class ECmp extends NodeComponent {
    @Override
    public void process() {
        System.out.println("ECmp executed!");
    }
}
```

```xml
<!-- D 不存在时，自动降级为 E 运行 -->
<chain name="chain1">
    THEN(A, B, C, node("D"));
</chain>
```

不同组件类型分别路由到对应类型的降级组件。例如布尔组件缺失走布尔降级、次数循环组件缺失走次数循环降级；与或非表达式（`AND`/`OR`/`NOT`）内部的 `node(...)` 缺失也会路由到布尔降级组件。

```xml
<chain name="chain2">
    IF(node("x1"), FOR("x2").DO(node("x3")));
</chain>
```

---

## 组件别名

给组件设置一个易记名称（通常是中文），别名会出现在步骤信息打印中。形式为 `组件ID[组件别名]<耗时毫秒>`。

- SpringBoot/Spring 扫描方式：`@LiteflowComponent(id = "a", name = "组件A")`
- 规则文件方式（非 Spring 工程）：在 `<node>` 上加 `name` 属性

```java
@LiteflowComponent(id = "a", name = "组件A")
public class ACmp extends NodeComponent {
    @Override
    public void process() { /* ... */ }
}
```

```xml
<node id="a" name="组件A" class="com.xxx.cmp.ACmp"/>
```

---

## 组件事件回调

在组件内重写生命周期方法，捕获组件执行成功/失败事件，回调内可通过 `getContextBean(...)` 拿到上下文。

- `onSuccess()`：`process()` 正常返回后回调
- `onError(Exception e)`：`process()` 抛异常后回调

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() { /* biz */ }

    @Override
    public void onSuccess() throws Exception {
        DefaultContext ctx = this.getContextBean(DefaultContext.class);
        // biz on success
    }

    @Override
    public void onError(Exception e) throws Exception {
        DefaultContext ctx = this.getContextBean(DefaultContext.class);
        // biz on error
    }
}
```

行为要点：
- `onError` 执行后，主方法抛出的异常仍会向上传播，`LiteflowResponse` 里的异常是主方法的异常，**整体流程仍是失败状态**。
- 若 `onError` 自身又抛异常，最终落到 response 的是**主方法**的异常；`onError` 的异常只会打出堆栈、不会抛出。
- 无论是否抛错，`afterProcess`（若实现）都会被执行。

---

## 组件回滚

流程执行失败且存在异常时，按**已执行组件的逆序**调用各组件的 `rollback()` 方法。版本：v2.11.0+。

- 回滚触发前提：组件未通过 `continueOnError`、EL 未设 `ignoreError`、RL 未用 `CATCH` 捕获，且出现异常。
- 逆序示例：执行顺序 `a -> b -> c -> d`，`d` 抛异常 → 回滚顺序 `d -> c -> b -> a`（仅回滚已执行完的组件，无法回滚未执行到的组件）。
- 回滚过程中若再次抛异常，**不会打断**整体回滚流程。

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() { /* biz */ }

    @Override
    public void rollback() throws Exception {
        DefaultContext ctx = this.getContextBean(DefaultContext.class);
        // undo biz
    }
}
```

回滚流程的步骤信息同样可从 `LiteflowResponse` 获取：

```java
LiteflowResponse response = flowExecutor.execute2Resp("yourChainName", "arg");
String rollbackStepStr           = response.getRollbackStepStr();         // 字符串形式
String rollbackStepStrWithTime   = response.getRollbackStepStrWithTime(); // 带耗时
Queue<CmpStep> rollbackStepQueue = response.getRollbackStepQueue();       // 步骤队列
Map<String, List<CmpStep>> rollbackSteps = response.getRollbackSteps();   // 按 nodeId 聚合
```

---

## 隐式子流程

在一个节点内部通过代码调用另一条链路，这条调用关系**不会**出现在规则文件中。主流程与隐式子流程**共享同一上下文**，子流程内可拿到本次请求的全部数据。版本：v2.15.0+ 已改版。

- 关键 API：`this.invoke2Resp(chainId, requestData)`，返回 `LiteflowResponse`
- 子流程内组件通过 `this.getRequestData()` 获取传入的请求参数（与旧版本不同）

```java
@Component("g")
public class GCmp extends NodeComponent {
    @Override
    public void process() throws Exception {
        LiteflowResponse response = this.invoke2Resp("otherChainId", "requestData");
        if (!response.isSuccess()) {
            throw response.getCause();
        }
    }
}
```

---

## 活跃规则保活策略

规则数量极大（上万至数十万）时，仅保留前 N 条最活跃的规则缓存，不活跃规则被临时卸载，下次首次调用时再重新编译入队。对使用者完全透明。版本：v2.15.0+。

```properties
# 开启保活策略
liteflow.chain-cache.enabled=true
# 保持活跃 chain 的数目，默认 10000
liteflow.chain-cache.capacity=10000
# 解析模式必须为 PARSE_ONE_ON_FIRST_EXEC（首次执行时单条解析）
liteflow.parse-mode=PARSE_ONE_ON_FIRST_EXEC
```

> 注意：`chain-cache.enabled=true` 时，`parse-mode` 必须为 `PARSE_ONE_ON_FIRST_EXEC`，否则不生效（源码 `FlowExecutor` 中有强校验）。

---

## 私有投递

一个组件可以为**指定 nodeId** 的组件投递一个或多个参数，这些参数只有目标组件能取到，且每个参数**只能被取一次**（内部用队列实现）。典型场景：同一组件被 `WHEN` 并发多次，每次需要不同入参。

- 发送：`this.sendPrivateDeliveryData(nodeId, data)`
- 接收：`this.getPrivateDeliveryData()`

```xml
<chain name="chain1">
    THEN(a, WHEN(b, b, b, b, b), c);
</chain>
```

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        for (int i = 0; i < 5; i++) {
            this.sendPrivateDeliveryData("b", i + 1);  // 向 b 投递 5 个不同参数
        }
    }
}

@LiteflowComponent("b")
public class BCmp extends NodeComponent {
    @Override
    public void process() {
        Integer value = this.getPrivateDeliveryData(); // 每个并发 b 各取一个，互不相同
        // biz
    }
}
```

---

## 组件切面

在组件执行前后/成功/失败处统一织入逻辑。提供两种方式。

### 1. 全局切面（推荐，LiteFlow 原生）

实现 `ICmpAroundAspect` 接口并注册为 Spring Bean，对**所有组件**生效。接口共 4 个方法：`beforeProcess` / `afterProcess` / `onSuccess` / `onError`。

```java
@Component
public class CmpAspect implements ICmpAroundAspect {
    @Override
    public void beforeProcess(NodeComponent cmp) {
        YourContextBean ctx = cmp.getContextBean(YourContextBean.class);
    }
    @Override
    public void afterProcess(NodeComponent cmp) { /* ... */ }
    @Override
    public void onSuccess(NodeComponent cmp) { /* ... */ }
    @Override
    public void onError(NodeComponent cmp, Exception e) { /* ... */ }
}
```

### 2. Spring Aspect 切面

用 `@Aspect` 按包名/规则切入任意组件的 `process()` 方法。

```java
@Aspect
public class CustomAspect {
    @Pointcut("execution(* com.yomahub.liteflow.test.aop.cmp1.*.process())")
    public void cut() {}

    @Around("cut()")
    public Object around(ProceedingJoinPoint jp) throws Throwable {
        // before
        Object ret = jp.proceed();
        // after
        return ret;
    }
}
```

---

## 步骤信息

通过 `LiteflowResponse` 获取流程执行的逐步信息，便于监控与排查。

- `Map<String, List<CmpStep>> getExecuteSteps()`：按 nodeId 聚合，**保留每个 nodeId 的全部步骤**（聚合进 List；与 `executor.md` 一致，源码 `LiteflowResponse.java:120`）。
- `Queue<CmpStep> getExecuteStepQueue()`：按**执行顺序**排列的全部步骤，同一组件出现 n 次即有 n 个 `CmpStep`。

`CmpStep` 关键方法：

| 方法 | 含义 | 起始版本 |
| --- | --- | --- |
| `isSuccess()` | 组件是否成功 | — |
| `getNodeId()` / `getNodeName()` | 组件 id / 别名 | — |
| `getTag()` | 组件标签 | — |
| `getTimeSpent()` | 耗时（毫秒） | — |
| `getException()` | 抛出的异常（success=false 不一定有，可能未执行到/未结束） | — |
| `getStepData()` / `setStepData(Object)` | 自定义 step 信息 | v2.13.0 |
| `getThreadName()` | 执行线程名 | v2.13.0 |
| `getStartTime()` / `getEndTime()` | 开始/结束时间（`Date`） | v2.11.4 |

```java
LiteflowResponse response = flowExecutor.execute2Resp("chain1", initParam, CustomContext.class);
Map<String, List<CmpStep>> stepMap  = response.getExecuteSteps();
Queue<CmpStep>            stepQueue = response.getExecuteStepQueue();
```

自定义步骤数据（v2.13.0+）：在组件中 `this.setStepData(obj)`，事后遍历 step 队列即可观察某个上下文值在每个组件处的快照。

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        this.setStepData("step_a");
    }
}

response.getExecuteStepQueue().forEach(s -> System.out.println(s.getStepData()));
```

---

## 异常

组件向外抛出的异常会被最外层执行器捕获并包装进 `LiteflowResponse`（并行编排中可用 `ignoreError` 不中断）。

```java
LiteflowResponse response = flowExecutor.execute2Resp("chain1", initParam, CustomContext.class);
if (!response.isSuccess()) {
    Exception e = response.getCause();
}
```

若需要从异常中取出业务 **code**，自定义异常需继承 `LiteFlowException`：

```java
public class YourException extends LiteFlowException {
    public YourException(String code, String message) {
        super(code, message);
    }
}
```

随后可从 response 直接取 code/message；若异常未实现 `LiteFlowException`，则 `code` 为 `null`，而 `message` 始终为 `exception.getMessage()`（非 null，除非异常本身无 message）。

```java
if (!response.isSuccess()) {
    String code    = response.getCode();
    String message = response.getMessage();
}
```

---

## 打印信息详解

### 执行过程中的日志

每个组件执行时会打印日志，格式 `请求ID:[O|X]start component[组件] execution`：
- `[O]`：执行了组件主逻辑。
- `[X]`：因 `isAccess()` 返回 `false` 未进入主逻辑。
- 行首的请求 ID 在整个请求链路中保持一致，便于定位。

关闭中间执行日志：

```properties
liteflow.print-execution-log=false
```

### 步骤链路打印

执行完整条链路后会自动打印步骤顺序，形式 `组件ID<耗时毫秒>`，例如：

```
a<100>==>c<10>==>m<0>==>q<200>
```

若组件设置了别名（见“组件别名”），打印会变为 `组件ID[组件别名]<耗时毫秒>`：

```
a[组件A]<100>==>b[组件B]<0>==>m[组件M]<256>
```

---

## 自定义请求 Id

把框架默认的请求 ID 替换为自己的规则，或把已有 TraceId 传入，使全链路日志共用同一前缀。

### 1. 自定义生成器

实现 `RequestIdGenerator` 接口，并通过配置注册：

```java
public class CustomRequestIdGenerator implements RequestIdGenerator {
    @Override
    public String generate() {
        return String.valueOf(System.nanoTime());
    }
}
```

```properties
liteflow.request-id-generator-class=com.xxx.CustomRequestIdGenerator
```

### 2. 传入已有 requestId / traceId（v2.10.5+）

调用 `execute2RespWithRid` 直接传入，链路内所有框架日志都会带上该 ID：

```java
LiteflowResponse response = flowExecutor.execute2RespWithRid("chain1", arg, "T001234", YourContext.class);
```

### 3. 让组件内业务日志也带请求 ID 前缀

把 slf4j 的 `Logger` 声明换成 LiteFlow 的 `LFLog`（继承自 slf4j `Logger`，用法完全一致）：

```java
private final LFLog logger = LFLoggerManager.getLogger(FlowExecutor.class);
```

---

## 快速解析模式

规则量极大（5000 条以上）时，开启后规则加载性能可提升约 4 倍。版本：v2.11.4+。

```properties
liteflow.fast-load=true
```

代价：牺牲热更新时的平滑性。正常模式下，热更新瞬间正在执行的流程会用**老链路**跑完，下次才用新链路；开启 fast-load 后，热更新瞬间执行中的流程可能前半段走老链路、后半段读到新链路，产生不一致。普通几百条规则的场景不建议开启。

---

## 不同格式规则加载

需要同时加载多种格式/多个文件规则源时使用（默认会解析失败）。

```properties
liteflow.rule-source=multipleType/flow.xml,multipleType/flow.json
liteflow.support-multiple-type=true
```

---

## 自定义组件执行器

替换或细化组件的执行逻辑（含重试策略）。默认执行器：`com.yomahub.liteflow.flow.executor.DefaultNodeExecutor`。如果不确定用途，建议保持默认。

- 自定义执行器需继承 `com.yomahub.liteflow.flow.executor.NodeExecutor`。
- 可全局替换，也可单组件覆盖；**单组件配置优先于全局**。

### 1. 全局替换

```properties
liteflow.node-executor-class=com.xxx.CustomerDefaultNodeExecutor
```

```java
public class CustomerDefaultNodeExecutor extends NodeExecutor {
    @Override
    public void execute(NodeComponent instance) throws Exception {
        LOG.info("使用 customerDefaultNodeExecutor 执行");
        super.execute(instance);
        // 可加入自定义代码，但至少要保证 instance.execute() 被调用
    }
}
```

### 2. 单组件覆盖

组件内重写 `getNodeExecutorClass()`：

```java
@LiteflowComponent("d")
public class DCmp extends NodeComponent {
    @Override
    public void process() { System.out.println("DCmp executed!"); }

    @Override
    public Class<? extends NodeExecutor> getNodeExecutorClass() {
        return CustomerNodeExecutorAndCustomRetry.class;
    }
}
```

> 重要：默认重试逻辑在 `DefaultNodeExecutor` 内实现。一旦使用自定义执行器，**全局重试参数与 `@LiteflowRetry` 都将失效**，重试策略需自己在执行器里实现（重试参数仍可读到，但需自行处理）。

---

## 简单监控

内置轻量监控，目前只统计一个指标：**每个组件的平均耗时**。默认每 5 分钟打印一次，按耗时倒序排列。

```properties
# 是否启用监控（默认 false）
liteflow.monitor.enable-log=false
# 监控队列大小
liteflow.monitor.queue-limit=200
# 首次打印的延迟（毫秒）
liteflow.monitor.delay=300000
# 打印间隔（毫秒）
liteflow.monitor.period=300000
```

---

## XML 的 DTD

为 XML 规则文件加 DTD 引用，便于编辑器校验与约束提示。版本：v2.9.1+。不加也不影响运行。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE flow PUBLIC  "liteflow" "https://liteflow.cc/liteflow.dtd">
<flow>
    <chain name="chain1">
        THEN(a,b,WHEN(c,d));
    </chain>
</flow>
```

---

## 常见坑 / 注意

- **降级组件**：规则中必须用 `node("xxx")` 包裹缺失组件才会触发降级；不加 `node` 直接报错。每种类型组件目前只允许一个 `@FallbackCmp`。`fallback-cmp-enable` 默认关闭，忘记开则降级完全不生效。
- **回滚**：只能回滚**已执行完**的组件，未执行到的组件不会回滚；回滚自身抛异常不会中断整体回滚；回滚前提是异常没被 `continueOnError` / `ignoreError` / `CATCH` 吞掉。
- **活跃规则保活**：`liteflow.chain-cache.enabled=true` 时，`parse-mode` **必须**为 `PARSE_ONE_ON_FIRST_EXEC`，否则策略不生效（源码有强校验）。
- **fast-load**：开了之后热更新不再平滑，执行中的流程可能前后半段不一致；几百条规则不要开。
- **自定义执行器**：一旦替换默认执行器，全局重试与 `@LiteflowRetry` 全部失效，重试要自己实现。
- **私有投递**：参数“只能取一次”，靠队列实现；若并发取数与投递数不匹配，多出的组件可能取到 `null`，需自行防御。
- **异常 code/message**：只有继承 `LiteFlowException` 的异常才能从 response 取到 `code`；`message` 对任何异常都是 `exception.getMessage()`（非 null，除非异常本身无 message）。
- **`onError` 回调**：抛出的依然是主方法异常；`onError` 自身抛错只会打堆栈不会外抛；`afterProcess` 无论成败都会执行。
- **步骤信息 Map vs Queue**：`getExecuteSteps()`（`Map<String,List<CmpStep>>`，按 nodeId 聚合、保留该 nodeId 全部步骤）与 `getExecuteStepQueue()`（按执行顺序的 Queue）**都保留全部步骤**，只是组织方式不同；按执行顺序排查用 Queue，按组件汇总用 Map。
- **隐式子流程**：主流程与子流程共享同一上下文；子流程取参统一走 `this.getRequestData()`（v2.15.0 改版后）。
- **请求 ID 日志**：要让组件内业务日志也带请求 ID 前缀，必须用 `LFLog`（`LFLoggerManager.getLogger(...)`），否则只有框架日志带前缀。
- **不同格式规则**：混合加载多格式/多源规则必须开 `support-multiple-type=true`，否则解析失败。
- **本地文件监听**：仅对 `rule-source` 指向的本地磁盘文件/模糊匹配文件生效，且需 `enable-monitor-file=true`。
