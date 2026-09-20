> 来源：`docs/04.v2.16.X文档/125.🌌异步中的线程池/`（010 说明 / 020 FlowExecutor 层面 / 030 组件异步层面 / 040 虚拟线程），对齐 LiteFlow **v2.16.X**（线程池模型自 v2.13.0 起重构；虚拟线程自 v2.15.0 起）。配置项与默认值已与 `liteflow-core` 的 `LiteflowConfig` 及 `ExecutorBuilder` 体系核对一致。

# 异步中的线程池

LiteFlow 中一切异步行为都落在两类线程池上。理解这两层的边界，是做容量规划、线程池隔离和虚拟线程切换的前提。

## 两层线程池总览

| 层 | 驱动场景 | 默认实现类 | 配置前缀 |
|---|---|---|---|
| **FlowExecutor 层（主执行器）** | `flowExecutor.execute2Future(...)` 返回 `Future<LiteflowResponse>` 的整条链路异步驱动；让主线程不在 `execute2Resp` 上阻塞 | `com.yomahub.liteflow.thread.LiteFlowDefaultMainExecutorBuilder` | `liteflow.main-executor-*` |
| **组件异步层（编排内并行）** | `WHEN(a,b,c)`；异步循环 `FOR/WHILE/ITERATOR(...).parallel(true).DO(...)`；`liteflow.when-thread-pool-isolate=true` 时的 WHEN 线程池隔离 | `com.yomahub.liteflow.thread.LiteFlowDefaultGlobalExecutorBuilder` | `liteflow.global-thread-pool-*` |

要点：
- FlowExecutor 层服务的是"整条链路跑在哪个池里"，只在用 `execute2Future` 时才相关；`execute2Resp` 同步返回不涉及这一层。
- 组件异步层服务的是"链路内部节点并行/异步执行时跑在哪个池里"，影响所有 WHEN 与异步循环。
- 两层各自独立配置。虚拟线程开关会影响 LiteFlow 默认 Builder；自定义 Builder 是否跟随取决于它调用的构建方法（见末节）。

## FlowExecutor 层：主执行器线程池

默认配置（`LiteflowConfig` 默认值）：

```properties
# 主执行器核心线程数，默认 64
liteflow.main-executor-works=64
# 主执行器 Builder 全限定类名
liteflow.main-executor-class=com.yomahub.liteflow.thread.LiteFlowDefaultMainExecutorBuilder
```

源码中默认 Builder 的实际池参数（`LiteFlowDefaultMainExecutorBuilder#buildExecutor`）：core = `mainExecutorWorks`、max = `mainExecutorWorks * 2`、队列容量固定 200、线程名前缀 `main-thread-`。

自定义主执行器线程池——实现 `ExecutorBuilder` 接口，并在配置中指定类名即可：

```java
package com.yourpkg.thread;

import com.yomahub.liteflow.thread.ExecutorBuilder;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CustomMainExecutorBuilder implements ExecutorBuilder {
    @Override
    public ExecutorService buildExecutor() {
        // 按需返回任意 ExecutorService，框架不关心如何构造
        return Executors.newCachedThreadPool();
    }
}
```

```properties
liteflow.main-executor-class=com.yourpkg.thread.CustomMainExecutorBuilder
```

使用入口（`execute2Future` 不阻塞，主线程后续从 `Future` 取 `LiteflowResponse`）：

```java
Future<LiteflowResponse> future = flowExecutor.execute2Future("chain1", requestParam, contextBean);
// 主线程继续做别的事 ...
LiteflowResponse resp = future.get();   // 需要结果时再阻塞获取
```

## 组件异步层：编排内并行线程池

组件异步层按**作用域从大到小**分三档：全局线程池 → Chain 层线程池 → 表达式层线程池。正常优先级为：

> **表达式层面 > Chain 层面 > 全局**

`when-thread-pool-isolate=true` 是额外规则：没有显式表达式线程池时，它仍会把每个 WHEN 提升为 condition 级隔离池，使用全局 Builder 按表达式 hash 分池，并覆盖 Chain 层线程池。因此完整优先级是：**表达式显式线程池 > WHEN 隔离池 > Chain 层 > 共享全局池**。该隔离开关只针对 WHEN，不改变并行循环的选择逻辑。

### 1. 全局线程池（默认共用）

```properties
# 全局异步节点线程池大小，默认 64
liteflow.global-thread-pool-size=64
# 全局异步节点线程池队列大小，默认 512
liteflow.global-thread-pool-queue-size=512
# 全局线程池 Builder，默认如下
liteflow.global-thread-pool-executor-class=com.yomahub.liteflow.thread.LiteFlowDefaultGlobalExecutorBuilder
```

源码中默认 Builder 的实际池参数（`LiteFlowDefaultGlobalExecutorBuilder#buildExecutor`）：core = max = `global-thread-pool-size`、队列容量 = `global-thread-pool-queue-size`、线程名前缀 `global-thread-`。

> 一旦你换成自定义 Builder，`global-thread-pool-size` 与 `global-thread-pool-queue-size` 即失效（这两个值是给默认 Builder 用的）。

### 2. Chain 层线程池（按链路隔离）

在 `<chain>` 上声明 `thread-pool-executor-class`，该链路内所有异步场景都走这个池：

```xml
<chain id="chain1"
       thread-pool-executor-class="com.yourpkg.thread.CustomChainExecutorBuilder">
    WHEN(a, b);
</chain>
```

```java
public class CustomChainExecutorBuilder implements ExecutorBuilder {
    @Override
    public ExecutorService buildExecutor() {
        // 自行构造，例如固定大小池
        return Executors.newFixedThreadPool(16);
    }
}
```

### 3. 表达式层线程池（最细粒度）

对单个 `WHEN` 或异步循环用 `.threadPool("全限定类名")` 指定：

```xml
<!-- WHEN 表达式级别 -->
<chain id="chain1">
    WHEN(c, d).threadPool("com.yourpkg.thread.CustomExprExecutorBuilder");
</chain>

<!-- 异步循环（必须 parallel(true)，否则 threadPool 无意义） -->
<chain id="chain2">
    FOR(2).parallel(true).DO(THEN(a,b,c))
          .threadPool("com.yourpkg.thread.CustomExprExecutorBuilder");
</chain>
```

```java
public class CustomExprExecutorBuilder implements ExecutorBuilder {
    @Override
    public ExecutorService buildExecutor() {
        return Executors.newFixedThreadPool(8);
    }
}
```

### WHEN 线程池隔离

```properties
# 默认 false。开启后每个 WHEN 表达式独占一个线程池，避免互相拖累
liteflow.when-thread-pool-isolate=true
```

线程池按 Builder 类名缓存。共享全局池和主执行器池若配置成**同一个 Builder 全限定类名**，会命中同一个缓存 key，实际复用同一个 `ExecutorService`；Chain／表达式／隔离池则在类名后追加对应对象 hash 形成独立池。需要真正隔离主执行器与全局池时，请使用不同的 Builder 类名。

### 默认丢弃策略

v2.13.0+ 默认线程池的拒绝策略为 `ThreadPoolExecutor.CallerRunsPolicy()`（源码 `ExecutorBuilder#buildDefaultExecutor` 确认）——即**不丢弃任务**，队列满时由调用线程亲自执行。高并发下若不想被反压，应主动放大线程池/队列或自定义 Builder。

> 附加（源码细节，文档未展开）：默认 Builder 全部经 `TtlExecutors.getTtlExecutorService(...)` 包装，因此异步线程中可正确传递 `TransmittableThreadLocal` 上下文；线程 `daemon=false`，keepAlive 60s，队列为 `ArrayBlockingQueue`。自定义 Builder 若直接返回普通 `ExecutorService`，框架不会在外层自动补 TTL 包装；需要透传 `TransmittableThreadLocal` 时，应调用 LiteFlow 的默认构建方法或自行使用 `TtlExecutors` 包装。

## 虚拟线程（JDK 21+）

> 版本支持：v2.15.0+。

JDK ≥ 21 时，LiteFlow 的两个**默认 Builder**会默认切换到虚拟线程。虚拟线程适合大量阻塞 IO；自定义 Builder 不一定受此开关控制。

```properties
# 默认 true。设为 false 可强制回到普通平台线程
liteflow.enable-virtual-thread=false
```

机制要点（源码 `ExecutorBuilder#buildDefaultExecutor`）：
- 开关开启时，调用 `Executors.newVirtualThreadPerTaskExecutor()`，此时 core/max/queue 参数全部被忽略——每个任务一个虚拟线程，不存在排队与拒绝。
- 两个默认 Builder（`LiteFlowDefaultMainExecutorBuilder`、`LiteFlowDefaultGlobalExecutorBuilder`）走的都是 `buildDefaultExecutor`，故开关对它们都生效。
- 自定义 Builder 只有调用 `ExecutorBuilder#buildDefaultExecutor(...)` 才跟随开关；直接自行创建线程池，或调用 `buildCommonExecutor(...)`，都不会自动切换为虚拟线程。

虚拟线程 vs 平台线程对照：

| 维度 | 虚拟线程（开关开） | 平台线程（开关关） |
|---|---|---|
| 触发条件 | JDK ≥ 21 且 `enable-virtual-thread=true`（默认） | JDK < 21，或显式设为 `false` |
| 并发上限 | 极高（百万级，受内存约束） | 受 core/max + 队列约束 |
| 容量调参 | 无需（core/max/queue 被忽略） | 需配合 size/queue/拒绝策略 |
| 适用场景 | IO 密集（大量阻塞调用） | CPU 密集 / 需要严格背压 |
| 回退方式 | `liteflow.enable-virtual-thread=false` | 默认即平台线程 |

> 留白/以源码为准：本文未覆盖 `when-thread-pool-isolate=true` 时每条 WHEN 池的具体构造参数（文档未给出，默认 Builder 复用同一套规则，详细数值建议直接看 `ExecutorBuilder` 与隔离相关实现）；`execute2Future` 以外是否存在其他主执行器入口、以及 `@LiteflowAsync` 风格注解与本层的关系，本组文档未提及，使用前请核对官方文档与源码。
