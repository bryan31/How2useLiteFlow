> 本文件内容来自 LiteFlow 当前 2.16.2 源码快照。文中 `@since 2.16.1` 表示功能首次引入版本；路径和行号会随提交漂移，定位时优先按类名／符号检索。
>
> ⚠️ **关于行号**：下方 `path:line` 已**逐条校准至当前源码**，但仍会随版本/commit 漂移。**类名、方法名、继承关系、调用链、算子→类映射表稳定可信，可直接依赖**；若你使用的版本不同，跳转到某行看代码前请**先用 `scripts/source-lookup.sh grep <符号名>` 按符号定位**，勿把行号当唯一锚点。

# LiteFlow 源码细节地图（code-internals）

面向想读懂/二次开发 LiteFlow 源码的工程师。本文只讲"代码如何实现"，每一节都给出真实文件与行号，重要处贴源码片段。

---

## 1. 启动与执行入口：FlowExecutor

`FlowExecutor` 是整个框架对外的执行门面（`liteflow-core/.../core/FlowExecutor.java:64`）。它的对外方法可以分两类：同步返回 `LiteflowResponse` 的 `execute2Resp(...)`，以及异步返回 `Future<LiteflowResponse>` 的 `execute2Future(...)`。

### 1.1 构造与初始化

构造器会同时做三件事：把自身放进 `FlowExecutorHolder`、按 `parseMode` 决定是否立刻解析规则、初始化 `DataBus`（`liteflow-core/.../core/FlowExecutor.java:81-92`）：

```java
public FlowExecutor(LiteflowConfig liteflowConfig) {
    this.liteflowConfig = liteflowConfig;
    LiteflowConfigGetter.setLiteflowConfig(liteflowConfig);
    FlowExecutorHolder.setHolder(this);
    if (!liteflowConfig.getParseMode().equals(ParseModeEnum.PARSE_ALL_ON_FIRST_EXEC)) {
        this.init(true);
    }
    // 初始化DataBus
    DataBus.init();
}
```

> 注意：只有 `PARSE_ALL_ON_START` 与 `PARSE_ONE_ON_FIRST_EXEC` 会在构造期调用 `init(true)`；`PARSE_ALL_ON_FIRST_EXEC` 延迟到首次执行。`PARSE_ONE_ON_FIRST_EXEC` 的真正延迟编译发生在 `Chain.execute`（见第 4、8 节）。

### 1.2 方法签名族

`execute2Resp` 有大量重载，最终都会汇聚到私有的 `doExecute(...)`（`liteflow-core/.../core/FlowExecutor.java:264` 起；核心私有方法 `execute2Resp(...)` 在 `:506-515`）：

```java
// liteflow-core/.../core/FlowExecutor.java:511
private LiteflowResponse execute2Resp(String chainId, Object param, String requestId, String conversationId,
        Class<?>[] contextBeanClazzArray, Object[] contextBeanArray, FlowEventListener eventListener) {
    Slot slot = doExecute(chainId, param, requestId, conversationId, contextBeanClazzArray,
            contextBeanArray, ChainExecuteModeEnum.BODY, eventListener);
    return LiteflowResponse.newMainResponse(slot);
}
```

异步版 `execute2Future(...)` 把 `cid/requestId` 在主线程解析定型后，丢给主线程池执行（`liteflow-core/.../core/FlowExecutor.java:422-435`）：

```java
public Future<LiteflowResponse> execute2Future(String chainId, Object param, ExecuteOption option) {
    ExecuteOption opt = option == null ? ExecuteOption.of() : option;
    String resolvedCid = resolveConversationId(opt);   // 必须主线程完成
    ...
    return ExecutorHelper.loadInstance()
            .buildMainExecutor(liteflowConfig.getMainExecutorClass())
            .submit(() -> FlowExecutorHolder.loadInstance().execute2Resp(
                    chainId, param, requestId, resolvedCid, ctxClasses, ctxBeans, eventListener));
}
```

### 1.3 执行主流程 doExecute（建 slot → 取 chain → 执行 → 回收）

`doExecute(...)`（`liteflow-core/.../core/FlowExecutor.java:533` 起，核心多参重载 `:533-535`）是核心调用链，流程为：

1. **懒初始化**：`FlowBus.needInit()`（CAS）触发一次 `init(true)`（`:536-538`）。
2. **分配 slot**：按传入是 class 数组还是 bean 数组选择 `DataBus.offerSlotByClass` 或 `DataBus.offerSlotByBean`（`:540-547`）。
3. **取 chain 并执行**：`FlowBus.getChain(chainId)` 后按 `ChainExecuteModeEnum` 调 `chain.execute` 或 `chain.executeRoute`（`:592-605`）。
4. **异常时回滚**：捕获异常后逆序遍历 `slot.getExecuteSteps()`，对标记了 `isRollback()` 的组件调用 `rollbackItem.rollback(slotIndex)`（`:613-638`，`descendingIterator` 在 `:625`、`rollback` 在 `:630`）。
5. **finally 回收 slot**：打印步骤、移除监听、`DataBus.releaseSlot(slotIndex)`（`:641-643`）。

```java
// liteflow-core/.../core/FlowExecutor.java:540
Integer slotIndex;
if (ArrayUtil.isNotEmpty(contextBeanClazzArray)) {
    slotIndex = DataBus.offerSlotByClass(ListUtil.toList(contextBeanClazzArray));
} else {
    slotIndex = DataBus.offerSlotByBean(ListUtil.toList(contextBeanArray));
}
if (slotIndex == -1) {
    throw new NoAvailableSlotException("there is no available slot");
}
```

---

## 2. 中央注册表：FlowBus

`FlowBus` 是一个纯静态工具类，承载链路（`chainMap`）、节点（`nodeMap`）、降级节点（`fallbackNodeMap`）、EL 去重（`elMd5Map`）四张注册表（`liteflow-core/.../flow/FlowBus.java:63-89`）。

### 2.1 并发集合与 fastLoad 的关键影响

`static` 块里根据 `liteflowConfig.getFastLoad()` 选择集合类型（`liteflow-core/.../flow/FlowBus.java:77-89`）：

```java
static {
    LiteflowConfig liteflowConfig = LiteflowConfigGetter.get();
    if (liteflowConfig.getFastLoad()){
        chainMap = new ConcurrentHashMap<>();
        nodeMap = new ConcurrentHashMap<>();
        fallbackNodeMap = new ConcurrentHashMap<>();
    } else {
        chainMap = new CopyOnWriteHashMap<>();
        nodeMap = new CopyOnWriteHashMap<>();
        fallbackNodeMap = new CopyOnWriteHashMap<>();
    }
    elMd5Map = new ConcurrentHashMap<>();
}
```

- **默认（`fastLoad=false`）**：`chainMap`/`nodeMap` 用 `CopyOnWriteHashMap`，写时复制，读多写少、热重载时不阻塞遍历——这就是热更新时正在执行的链路能"读老引用"的底层保障。
- **`fastLoad=true`**：改用 `ConcurrentHashMap`，去掉写时复制开销，主打高吞吐；代价是热重载一致性弱化（适合规则基本不变的"快加载"场景）。

### 2.2 链路注册与获取

| 方法 | 作用 | 行号 |
| --- | --- | --- |
| `getChain(String)` | 从 `chainMap` 取 | `FlowBus.java:91` |
| `addChain(String chainId)` | **第一阶段**预装载：放一个空壳 `new Chain(chainId)` 占位 | `FlowBus.java:96-100` |
| `addChainPhase1(Chain)` | 第一阶段：直接 `put`，用于 parser 先放占位 | `FlowBus.java:102-104` |
| `addChain(Chain)` | **第二阶段**：替换为编译好的 chain，前后触发 `postProcessBefore/AfterChainBuild` 生命周期，并写 `elMd5Map` | `FlowBus.java:107-127` |
| `containChain(String)` / `getChainMap()` | 包含判断 / 暴露整张表 | `FlowBus.java:129` / `:361` |

### 2.3 节点注册

`addNode` 系列（`FlowBus.java:174-351`）。核心私有 `addNode(...)` 在 `:310`，内部走 `getNodeComponentList(...)`（`:238`，处理声明式组件动态代理 / Spring 容器 / 反射 new 三条路径），再 `addCompiledNode2Map(...)`（`:289`，脚本节点会 `loadScript` 并 `setCompiled(true)`）。`put2NodeMap(...)`（`:498`）是统一入口，前后触发 `postProcessBefore/AfterNodeBuild` 生命周期。

### 2.4 热重载 / 清理 / 卸载

- `reloadChain(chainId, elContent[, routeContent])`（`FlowBus.java:486-492`）：本质是用 `LiteFlowChainELBuilder` 重建并替换。
- `reloadScript(nodeId, script)`（`:455`）：更新 node 与所有引用该 node 的 chain 中的脚本，并调 `ScriptExecutor.load`。
- `cleanCache()`（`:370`）：先 `cleanMonitorFile()` 停文件监听，再清空四张表与脚本缓存。
- `removeChain(String)`（`:418`）、`removeNode(String)`（`:437`）、`unloadScriptNode(String)`（`:472`）。

---

## 3. Slot 与 DataBus：slot 池机制

### 3.1 Slot 是什么

`Slot` 是单次执行的“执行槽／上下文容器”，内部用 `ConcurrentHashMap metaDataMap` 存各类元数据（chainId、requestId、conversationId、exception、各 condition 的结果等），并用 `List<Tuple> contextBeanList` 存放业务上下文 bean（`liteflow-core/.../slot/Slot.java:93-95`，`metaDataMap` 在 `:93`、`contextBeanList` 在 `:95`）。**请求隔离来自每次执行分配独立 Slot**；`TransmittableThreadLocal` 用于把当前执行相关的线程局部信息传到线程池任务，不是上下文隔离机制。一个 Slot 内的 WHEN 分支共享同一批上下文对象，并发安全仍由业务保证。

业务上下文通过 `getContextBean(Class)` / `getContextBean(String key)` 取出，按类或 `@ContextBean` 的 key 匹配（`Slot.java:537-553`）：

```java
public <T> T getContextBean(Class<T> contextBeanClazz) {
    Tuple contextTuple = contextBeanList.stream()
        .filter(tuple -> contextBeanClazz.isAssignableFrom(tuple.get(1).getClass()))
        .findFirst().orElse(null);
    if (contextTuple == null) { ... throw new NoSuchContextBeanException(...); }
    return contextTuple.get(1);
}
```

`@ContextBean`（`liteflow-core/.../context/ContextBean.java:16`）标注上下文 bean 的别名。

### 3.2 DataBus：slot 池的分配与回收

`DataBus`（`liteflow-core/.../slot/DataBus.java:37`）用 `ConcurrentHashMap<Integer, Slot> SLOTS` + `ConcurrentLinkedQueue<Integer> QUEUE`（一个空闲下标队列）实现对象池（`DataBus.java:48-50`）。注释解释了为何用 ConcurrentHashMap 而非数组（`:43-47`）。

- `init()`（`:63`）：读 `slotSize`（默认 1024，见第 10 节），把 `[0, slotSize)` 全放进 `QUEUE`。
- `offerSlotByClass` / `offerSlotByBean`（`:75` / `:85`）：反射构造上下文 bean，包成 `Tuple(key, bean)` 列表，`new Slot(contextBeanList)`，再 `offerIndex(slot)`。
- `offerIndex(slot)`（`:102`）：从 `QUEUE.poll()` 取下标；取不到时 `synchronized` 扩容 `*1.75`（`:113-125`），再 `SLOTS.put(slotIndex, slot)` 并 `OCCUPY_COUNT++`。
- `releaseSlot(slotIndex)`（`:150`）：`SLOTS.remove` + `QUEUE.add(slotIndex)` + `OCCUPY_COUNT--`。

```java
// liteflow-core/.../slot/DataBus.java:102
private static int offerIndex(Slot slot) {
    try {
        Integer slotIndex = QUEUE.poll();
        if (ObjectUtil.isNull(slotIndex)) {
            synchronized (DataBus.class) {
                slotIndex = QUEUE.poll();
                if (ObjectUtil.isNull(slotIndex)) {
                    int nextMaxIndex = (int) Math.round(currentIndexMaxValue * 1.75);
                    QUEUE.addAll(IntStream.range(currentIndexMaxValue, nextMaxIndex)...);
                    currentIndexMaxValue = nextMaxIndex;
                    slotIndex = QUEUE.poll();
                }
            }
        }
        if (ObjectUtil.isNotNull(slotIndex)) {
            SLOTS.put(slotIndex, slot);
            OCCUPY_COUNT.incrementAndGet();
            return slotIndex;
        }
    } ...
}
```

> `slot-size` 只是初始数量，不是固定容量；空闲下标耗尽通常会自动扩容。`offerIndex` 只有在扩容仍未产生可用下标（例如初始值为 0）或内部出现异常时才返回 `-1`，随后由 `doExecute` 抛 `NoAvailableSlotException`（`FlowExecutor.java:549-550`）。因此不能把初始 `slot-size` 或 Metrics 的同名 Gauge 当成实时容量上限。

---

## 4. Chain → Condition 树

### 4.1 两层结构

- `Chain`（`liteflow-core/.../flow/element/Chain.java:39`，`implements Executable`）持有一组 `List<Condition> conditionList`（字段 `:47`，getter `getConditionList` 在 `:80`）。执行时按顺序调用每个 `condition.execute(slotIndex)`（`Chain.java:152-155`）。
- `Condition`（`liteflow-core/.../flow/element/Condition.java`，`implements Executable`）是抽象基类，其 `execute(slotIndex)` 会先把自身压入 `slot.pushCondition(this)`、调 `executeCondition(slotIndex)`、最后 `slot.popCondition()`（`Condition.java:execute(...)`）——这个 Condition 栈就是 `getCurrentCondition()` 能拿到当前所在 condition 的原因。

```java
// liteflow-core/.../flow/element/Condition.java
@Override
public void execute(Integer slotIndex) throws Exception {
    Slot slot = DataBus.getSlot(slotIndex);
    try {
        slot.pushCondition(this);
        executeCondition(slotIndex);
    } catch (ChainEndException e) { throw e; }
    catch (Exception e) { slot.setException(e); throw e; }
    finally { slot.popCondition(); }
}
```

### 4.2 Condition 实现类层级（真实类名）

全部位于 `liteflow-core/.../flow/element/condition/`。继承关系（来自源码 `extends` 声明）：

```
Condition（抽象基类，flow/element/Condition.java）
├── ThenCondition                              （串行）
│   └── RetryCondition                         （重试包裹）
├── WhenCondition                              （并行）
│   └── TimeoutCondition                       （超时包裹）
├── LoopCondition（循环基类）
│   ├── ForCondition                           （FOR 次数循环）
│   ├── WhileCondition                         （WHILE 条件循环）
│   └── IteratorCondition                      （ITERATOR 迭代循环）
├── IfCondition                                （IF/ELIF/ELSE）
├── SwitchCondition                            （SWITCH 选择）
├── CatchCondition                             （CATCH 异常捕获）
├── AndOrCondition                             （AND / OR 布尔组合）
├── NotCondition                               （NOT 取反）
├── PreCondition                               （PRE 前置）
├── FinallyCondition                           （FINALLY 后置）
├── AbstractCondition                          （抽象 chain 占位，执行抛 ChainNotImplementedException）
└── ChainBindWrapperCondition                  （bind 包裹）
```

> 注意：源码里**没有**独立命名的 `ForCondition` 之外的 "ThenCondition/WhenCondition" 之外的循环类；循环统一继承 `LoopCondition`。`PreCondition`/`FinallyCondition` 是独立类（非 condition 之外的"标记接口"）。

### 4.3 executeCondition 的执行模式

每个子类的 `executeCondition(Integer slotIndex)` 体现该算子的语义。典型例：

- **ThenCondition**（`condition/ThenCondition.java`）：先执行所有 `PreCondition`，再顺序执行 `getExecutableList()`，`finally` 执行所有 `FinallyCondition`；捕获 `ChainEndException` 单独向上抛（`isEnd` 语义）。
- **WhenCondition**（`condition/WhenCondition.java:executeCondition`）：委托 `executeAsyncCondition`，按 `ParallelStrategyEnum`（ALL/ANY/MUST/PERCENTAGE）经 `ParallelStrategyHelper` 走并行调度。
- **IfCondition**（`condition/IfCondition.java`）：先 `ifItem.isAccess` → `ifItem.execute` → 取 boolean 结果 → 选 true/false 分支执行；分支不能是 Pre/Finally。
- **SwitchCondition**（`condition/SwitchCondition.java:executeCondition`）：执行 switch 节点取 targetId，按 `id` 或 `tag:id` 模式匹配 targetList，未匹配走 `DEFAULT`。
- **ForCondition**（`condition/ForCondition.java:executeCondition`）：执行 forNode 取 `forCount`，按串行/并行（`isParallel`）循环 `executableItem`，每轮可执行 break 节点。
- **WhileCondition / IteratorCondition**：结构类似，分别以 `getWhileResult` 和 `Iterator.hasNext()` 作为循环条件。

> 所以 EL 表达式 `THEN(a, IF(b, c, d), WHEN(e, f))` 被解析后，就是一棵 `ThenCondition → [Node, IfCondition, WhenCondition]` 的树；执行即树的深度优先遍历。

---

## 5. 两阶段解析（解决循环依赖）

LiteFlow 把"注册 chain 占位"与"编译 EL 成 Condition 树"分成两个阶段，从而允许 chain 之间互相引用（循环依赖）。入口在 `ParserHelper`（`liteflow-core/.../parser/helper/ParserHelper.java`）。

### 5.1 阶段一：放占位

`parseChainDocument(...)`（XML）/ JSON 版（`ParserHelper.java:135` 与 `:223` 附近）都遵循同一模式：先遍历所有 chain 元素，构造 `Chain` 对象但**不编译**，调 `FlowBus.addChainPhase1(chain)` 放进 `chainMap`（`ParserHelper.java:159-161`）：

```java
// ParserHelper.java:157
Chain chain = parseOneChain(e);
if (chain != null){
    FlowBus.addChainPhase1(chain);
}
```

注释明确写："先放有一个好处，可以在 parse 的时候先映射到 FlowBus 的 chainMap，然后再去解析，这样就不用去像之前的版本那样回归调用，同时也解决了不能循环依赖的问题"（`ParserHelper.java:137-139`）。

### 5.2 阶段二：真正编译

清空去重集合后，遍历 `FlowBus.getChainMap()`，对非抽象且未编译的 chain 调 `LiteFlowChainELBuilder.fromChain(chain).build()`（`ParserHelper.java:171-184`，`fromChain(...).build()` 在 `:182`）：

```java
// ParserHelper.java:171
FlowBus.getChainMap().entrySet().forEach(entry -> {
    Chain chain = entry.getValue();
    if (BooleanUtil.isTrue(chain.isAbstract())) { return; }
    processChainInheritance(chain, processedChainIds);   // 处理抽象 chain 继承
    if (BooleanUtil.isFalse(chain.isCompiled())) {
        LiteFlowChainELBuilder.fromChain(chain).build();
    }
});
```

### 5.3 编译细节：级联先行解析

`LiteFlowChainELBuilder.compile(...)`（`liteflow-core/.../builder/el/LiteFlowChainELBuilder.java:344`）在真正用 QLExpress 执行 EL 前，会先扫出 EL 里引用的外部变量名，对其中"已注册但未编译"的子 chain 先行 `buildUnCompileChain`（`LiteFlowChainELBuilder.java:361-371`），避免循环场景里 index/obj 无法设置：

```java
// LiteFlowChainELBuilder.java:363
Set<String> itemSet = EXPRESS_RUNNER.getOutVarNames(elStr);
itemSet.forEach(item -> {
    if (FlowBus.containChain(item) && ObjectUtil.notEqual(chain.getChainId(), item)) {
        Chain itemChain = FlowBus.getChain(item);
        if (!itemChain.isCompiled()){
            buildUnCompileChain(FlowBus.getChain(item));
        }
    }
});
```

最终用 `EXPRESS_RUNNER.execute(elStr, context, ...)` 把 EL 跑成一个最外层 `Condition`（`LiteFlowChainELBuilder.java:376`），上下文里预先放了所有 chain 与 node 的映射（`:347-359`）。

### 5.4 延迟编译（PARSE_ONE_ON_FIRST_EXEC）

`Chain.execute` 在执行前若发现 `isCompiled=false`，会在 `synchronized(this)` 双检锁内调 `LiteFlowChainELBuilder.buildUnCompileChain(this)`（`liteflow-core/.../flow/element/Chain.java:121-127`，`buildUnCompileChain` 调用在 `:124`）——这就是 `PARSE_ONE_ON_FIRST_EXEC` 的懒编译点。

---

## 6. 组件继承体系与生命周期钩子

### 6.1 类层级（真实类名）

全部在 `liteflow-core/.../core/`：

```
NodeComponent（抽象基类，core/NodeComponent.java:52，构造器在 :84）
├── NodeBooleanComponent   （abstract processBoolean()，core/NodeBooleanComponent.java:11）
│   └── ScriptBooleanComponent   （implements ScriptComponent）
├── NodeSwitchComponent    （abstract processSwitch()，core/NodeSwitchComponent.java:27）
│   └── ScriptSwitchComponent
├── NodeForComponent       （abstract processFor()，core/NodeForComponent.java:13）
│   └── ScriptForComponent
├── NodeIteratorComponent  （abstract processIterator()，core/NodeIteratorComponent.java）
│   └── （无 ScriptIteratorComponent——脚本组件只有 Common/Boolean/Switch/For 四类，`NodeTypeEnum` 无 `ITERATOR_SCRIPT`；迭代循环必须使用 Java `NodeIteratorComponent`，`for_script` 不能替代）
└── ScriptCommonComponent  （extends NodeComponent implements ScriptComponent）
```

脚本组件与类型的映射由 `ScriptComponent.ScriptComponentClassMap` 维护（`liteflow-core/.../core/ScriptComponent.java:20-27`）：

```java
Map<NodeTypeEnum, Class<?>> ScriptComponentClassMap = new HashMap<NodeTypeEnum, Class<?>>() {{
    put(NodeTypeEnum.SCRIPT, ScriptCommonComponent.class);
    put(NodeTypeEnum.SWITCH_SCRIPT, ScriptSwitchComponent.class);
    put(NodeTypeEnum.BOOLEAN_SCRIPT, ScriptBooleanComponent.class);
    put(NodeTypeEnum.FOR_SCRIPT, ScriptForComponent.class);
}};
```

> `NodeForComponent.process()` 把 `processFor()` 的 int 写进 `slot.setForResult(...)`（`NodeForComponent.java:16-19`）；`NodeBooleanComponent` 写 `slot.setIfResult(...)`（`NodeBooleanComponent.java`）；`NodeSwitchComponent` 写 `slot.setSwitchResult(...)`（`NodeSwitchComponent.java:30-33`）；`NodeIteratorComponent` 写 `slot.setIteratorResult(...)`。这些写入就是第 4 节各 Condition 能用 `getItemResultMetaValue(slotIndex)` 读到结果的来源。

### 6.2 生命周期钩子及其调用点

钩子方法的默认实现集中在 `NodeComponent`（`liteflow-core/.../core/NodeComponent.java`）。**真正的调用发生在 `NodeComponent.execute()` 里**（`NodeComponent.java:95-166`），通过 `self`（代理后的自身）来调，便于切面/AOP 生效：

```java
// NodeComponent.java:95
public void execute() throws Exception {
    ...
    try {
        self.beforeProcess();   // 前置处理       (:116)
        self.process();         // 主逻辑         (:119)
        self.onSuccess();       // 成功回调       (:122)
        cmpStep.setSuccess(true);
    } catch (Exception e) {
        cmpStep.setSuccess(false);
        try { self.onError(e); }  // 失败回调     (:135)
        throw e;
    } finally {
        self.afterProcess();     // 后置处理      (:145)
        ...
    }
}
```

各钩子的默认实现 / 调用点：

| 钩子 | 默认实现位置 | 调用点 | 说明 |
| --- | --- | --- | --- |
| `isAccess()` | `NodeComponent.java:232`（默认 `true`） | 由各 `Condition.executeCondition` 在执行节点前判断（如 `IfCondition.java`、`SwitchCondition.java:39`、`ForCondition.java:41`） | 返回 false 则跳过该节点/整个表达式 |
| `beforeProcess()` | `NodeComponent.java`（经 `CmpAroundAspectHolder`） | `execute()` `:116` | 切面 `ICmpAroundAspect.beforeProcess` |
| `process()` | 子类实现（如 `NodeForComponent.process`） | `execute()` `:119` | 真正业务逻辑 |
| `onSuccess()` | `NodeComponent.java` | `execute()` `:122` | 成功后回调 |
| `onError(Exception)` | `NodeComponent.java` | `execute()` `:135` | 失败后回调，本身抛错只打日志 |
| `isContinueOnError()` | `NodeComponent.java:237`（默认 `false`） | 由 condition/executor 判断 | 出错是否继续 |
| `isEnd()` | `NodeComponent.java:242`（读 `refNode.getIsEnd()`） | 由 condition 判断；为 true 抛 `ChainEndException` | 是否结束整个流程 |
| `afterProcess()` | `NodeComponent.java:227` | `execute()` `:145`（finally） | 切面 `afterProcess` |
| `rollback()` | 由子类覆写 | `doRollback()`（`NodeComponent.java:168`），由 `FlowExecutor.doExecute` 异常分支逆序调用（`FlowExecutor.java:625-632`，`descendingIterator` 在 `:625`、`rollback` 在 `:630`） | 回滚；构造器反射探测是否覆写以置 `isRollback`（`NodeComponent.java:84-92`） |

脚本组件（`ScriptCommonComponent`／`ScriptBooleanComponent`／`ScriptSwitchComponent`／`ScriptForComponent`）覆写了全部钩子，把它们转交给 `ScriptExecutor.executeXxx(wrap)` 执行（见 `ScriptBooleanComponent.java:35-84`，其余类型同构）。

> `rollback` 是否生效取决于构造时的反射探测：`NodeComponent` 构造器尝试 `clazz.getDeclaredMethod("rollback")`，找到就 `setRollback(true)`（`NodeComponent.java:84-92`）。`FlowExecutor` 异常时只回滚标记为 rollback 的组件。

> 补充（v2.16.1）：除上述组件级钩子外，框架级生命周期新增 **`PostProcessNodeExecuteLifeCycle`** 接口（`liteflow-core/.../lifecycle/PostProcessNodeExecuteLifeCycle.java`），调用点同样在 `NodeComponent.execute()` 内——before 钩子在主逻辑执行前统一回调（`NodeComponent.java:119-127`，回调语句在 `:122`，钩子自身抛错只记日志）；生命周期 after 位于 `finally` 后半段，携带耗时 `timeSpent` 与异常引用（成功为 `null`）（`:184-188`，回调语句在 `:187`）。业务逻辑异常本身不会跳过它，但前面的组件级 `afterProcess()` 若抛错，控制流不会到达该回调。`LifeCycleHolder` 为其新增独立列表与分发分支（`lifecycle/LifeCycleHolder.java:25`、`:39-41`，getter 在 `:64-66`）。接口用法详见 [lifecycle.md](./lifecycle.md)。

---

## 7. EL 算子 → Operator 实现类映射

所有算子都在 `liteflow-core/.../builder/el/operator/`，均继承 `BaseOperator<T extends Executable>`（`builder/el/operator/base/BaseOperator.java`，实现 QLExpress4 的 `QLFunctionalVarargs`）。算子与 EL 关键字的绑定发生在 `QlExpressUtils` 的 static 块（`liteflow-core/.../util/QlExpressUtils.java:30-70`）。完整映射表（关键字值来自 `common/ChainConstant.java`）：

| EL 关键字（实际值） | Operator 类 | 注册方式 | 产生的 Condition/作用 |
| --- | --- | --- | --- |
| `THEN` / `SER` | `ThenOperator` | `addVarArgsFunction` | `ThenCondition` |
| `WHEN` / `PAR` | `WhenOperator` | `addVarArgsFunction` | `WhenCondition` |
| `SWITCH` | `SwitchOperator` | `addVarArgsFunction` | `SwitchCondition` |
| `PRE` | `PreOperator` | `addVarArgsFunction` | `PreCondition` |
| `FINALLY` | `FinallyOperator` | `addVarArgsFunction` | `FinallyCondition` |
| `IF` | `IfOperator` | `addVarArgsFunction` | `IfCondition` |
| `node` / `NODE` | `NodeOperator` | `addVarArgsFunction`（大小写各注册一次） | 引用一个 Node |
| `FOR` | `ForOperator` | `addVarArgsFunction` | `ForCondition` |
| `WHILE` | `WhileOperator` | `addVarArgsFunction` | `WhileCondition` |
| `ITERATOR` | `IteratorOperator` | `addVarArgsFunction` | `IteratorCondition` |
| `CATCH` | `CatchOperator` | `addVarArgsFunction` | `CatchCondition` |
| `AND` | `AndOperator` | `addVarArgsFunction` | `AndOrCondition` |
| `OR` | `OrOperator` | `addVarArgsFunction` | `AndOrCondition` |
| `NOT` | `NotOperator` | `addVarArgsFunction` | `NotCondition` |
| `ELSE` | `ElseOperator` | `addExtendFunction` | IF 的 false 分支 |
| `ELIF` | `ElifOperator` | `addExtendFunction` | IF 的 else-if |
| `TO` / `to` | `ToOperator` | `addExtendFunction`（大小写各一次） | SWITCH 的 target 列表 |
| `DEFAULT` | `DefaultOperator` | `addExtendFunction` | SWITCH 默认分支 |
| `tag` | `TagOperator` | `addExtendFunction` | 设置 tag |
| `any` | `AnyOperator` | `addExtendFunction` | WHEN 的 any 策略 |
| `must` | `MustOperator` | `addExtendFunction` | WHEN 的 must 策略 |
| `percentage` | `PercentageOperator` | `addExtendFunction` | WHEN 的百分比策略 |
| `id` | `IdOperator` | `addExtendFunction` | 设置 id |
| `ignoreError` | `IgnoreErrorOperator` | `addExtendFunction` | WHEN 忽略错误 |
| `threadPool` | `ThreadPoolOperator` | `addExtendFunction` | 指定线程池 |
| `DO` | `DoOperator` | `addExtendFunction` | 循环体 |
| `BREAK` | `BreakOperator` | `addExtendFunction` | 循环中断 |
| `data` | `DataOperator` | `addExtendFunction` | 设置 cmpData |
| `maxWaitSeconds` | `MaxWaitSecondsOperator` | `addExtendFunction` | 超时秒 |
| `maxWaitMilliseconds` | `MaxWaitMillisecondsOperator` | `addExtendFunction` | 超时毫秒 |
| `parallel` | `ParallelOperator` | `addExtendFunction` | 循环并行开关 |
| `retry` | `RetryOperator` | `addExtendFunction` | 重试包裹 |
| `bind` | `BindOperator` | `addExtendFunction` | 数据绑定 |

绑定源码（节选，`QlExpressUtils.java:32-68`）：

```java
EXPRESS_RUNNER.addVarArgsFunction(ChainConstant.THEN, new ThenOperator());
EXPRESS_RUNNER.addVarArgsFunction(ChainConstant.WHEN, new WhenOperator());
EXPRESS_RUNNER.addVarArgsFunction(ChainConstant.SER, new ThenOperator());   // SER=THEN 别名
EXPRESS_RUNNER.addVarArgsFunction(ChainConstant.PAR, new WhenOperator());   // PAR=WHEN 别名
...
EXPRESS_RUNNER.addExtendFunction(ChainConstant.RETRY, Object.class, new RetryOperator());
EXPRESS_RUNNER.addExtendFunction(ChainConstant.BIND, Object.class, new BindOperator());
```

> 补充：目录下还存在 `MaxWaitTimeOperator.java` 文件，但 `QlExpressUtils` 中**未注册它**——对外暴露的是 `MaxWaitSecondsOperator` / `MaxWaitMillisecondsOperator`（`ChainConstant.MAX_WAIT_SECONDS="maxWaitSeconds"` / `MAX_WAIT_MILLISECONDS="maxWaitMilliseconds"`，`ChainConstant.java:106-108`）。

`BaseOperator.call(...)`（`base/BaseOperator.java`）捕获 `QLException` 并把其它异常包成 `ELParseException`，真正构造逻辑在各 `build(Object[] objects)` 里。

---

## 8. 解析模式 ParseModeEnum 与解析时机

枚举定义（`liteflow-core/.../enums/ParseModeEnum.java`）：

```java
public enum ParseModeEnum {
    PARSE_ALL_ON_START,        // 启动时解析所有规则
    PARSE_ALL_ON_FIRST_EXEC,   // 第一次执行链路时解析所有规则
    PARSE_ONE_ON_FIRST_EXEC    // 第一次执行相关链路时解析当前规则
}
```

各模式的解析时机（由 `FlowExecutor` 构造器与 `init`、`Chain.execute` 协同实现）：

| 模式 | 何时调 `init(true)` 解析全部 | 何时编译单个 chain | 关键源码 |
| --- | --- | --- | --- |
| `PARSE_ALL_ON_START` | 构造期（构造器里 `parseMode != PARSE_ALL_ON_FIRST_EXEC` 即调） | 启动时一次性编译完成 | `FlowExecutor.java:87-89`（构造期 `init(true)`） |
| `PARSE_ALL_ON_FIRST_EXEC` | **不**在构造期；首次 `doExecute` 时 `FlowBus.needInit()`（CAS）触发 `init(true)` | 同上，整体解析 | `FlowExecutor.java:87`（条件不成立跳过）、`FlowExecutor.java:536-538` |
| `PARSE_ONE_ON_FIRST_EXEC` | 构造期也调 `init(true)`，但 parser 只走"阶段一注册占位"，不真正编译 | **首次执行该 chain** 时，在 `Chain.execute` 双检锁内 `buildUnCompileChain` | `Chain.java:117-128`；脚本节点同理延后（`FlowBus.addScriptNode` `:209-219`） |

> 对 `PARSE_ONE_ON_FIRST_EXEC`，`FlowBus.addScriptNode` 会跳过立即编译，只 `put2NodeMap` 一个未编译 node（`FlowBus.java:209-219`）。

> ⚠️ **Spring Boot 下的真实启动链路**：Spring 实际用**无参** `new FlowExecutor()`（`LiteflowMainAutoConfiguration.java:49`），上面提到的"构造期 `init(true)`"**并非发生在构造器里**，而是由 `LiteflowExecutorInit`（`SmartInitializingSingleton` 的 `afterSingletonsInstantiated`）在所有单例就绪后触发。`init(true)`/构造器内解析只在**非 Spring、或直接 `new FlowExecutor(config)`** 的路径里于构造期发生。

---

## 9. 热重载 / 文件监听

### 9.1 MonitorFile

文件监听由 `MonitorFile`（`liteflow-core/.../monitor/MonitorFile.java:23`，单例 `Singleton.get`）实现，基于 `commons-io` 的 `FileAlterationMonitor/Observer`。监听路径通过 `addMonitorFilePath(s)` 收集到 `PATH_SET`（`:43-60`）。

`create()`（`:64`）为每个路径建 `FileAlterationObserver`，在 `onFileChange/onFileDelete/onFileCreate` 回调里调内部 `reloadRule()`（`:95`），它最终调 `FlowExecutorHolder.loadInstance().reloadRule()`（`:97`）。轮询间隔 `interval = 2ms`（`MonitorFile.java:73`，写成 `MILLISECONDS.toMillis(2)`，实际即 2 毫秒）：

```java
// MonitorFile.java:77
FileAlterationObserver observer = new FileAlterationObserver(new File(path));
observer.addListener(new FileAlterationListenerAdaptor() {
    @Override public void onFileChange(File file) { this.reloadRule(); }
    ...
    private void reloadRule() {
        try { FlowExecutorHolder.loadInstance().reloadRule(); }
        catch (Exception e) { LOG.error("reload rule error", e); }
    }
});
FileAlterationMonitor monitor = new FileAlterationMonitor(interval, observer);
monitor.start();
monitors.add(monitor);
```

`destroy()`（`:117`）逐个 `monitor.stop(1000)` 并清空集合——`FlowBus.cleanCache()`/`cleanMonitorFile()` 会调它（`FlowBus.java:393-400`）。

### 9.2 启用条件

`FlowExecutor.init(isStart)` 的末尾：仅当 `isStart && liteflowConfig.getEnableMonitorFile()` 时才 `addMonitorFilePaths` + `MonitorFile.create()`（`FlowExecutor.java:228-236`，对应配置 `liteflow.enable-monitor-file`，默认 `false`）。

### 9.3 copy-on-write 与 fastLoad 的影响

热重载时正在执行的链路不会读到"半截"数据，依赖两点（见第 2 节）：

- **默认**：`chainMap`/`nodeMap` 是 `CopyOnWriteHashMap`，写时复制整引用；`Chain.execute` 在执行前会先把 `this.conditionList` 的引用拷贝到局部变量 `conditionListRef`，即便中途被重载置空，本次仍用老引用跑完（拷贝语句 `conditionListRef = this.conditionList` 在 `Chain.java:132`、`buildTemporaryConditionList` 兜底）。
- **`fastLoad=true`**：改用 `ConcurrentHashMap`，写更快但无写时复制，热重载一致性弱（`FlowBus.java:79-87`）。所以 `fastLoad` 适合"启动快 + 规则基本不热更"的场景。

---

## 10. 配置 LiteflowConfig

`LiteflowConfig`（`liteflow-core/.../property/LiteflowConfig.java`）是 POJO。配置 key 由 Spring Boot starter 通过 `@ConditionalOnProperty(prefix="liteflow", ...)` 与 `liteflow-default.properties` 暴露（`liteflow-spring-boot-starter/.../META-INF/liteflow-default.properties`、`LiteflowMainAutoConfiguration.java:28/58/64`）。下表列出关键字段、对应配置 key、默认值与行号。

| 字段（LiteflowConfig） | 配置 key | 默认值 | 字段行号 |
| --- | --- | --- | --- |
| `enable` | `liteflow.enable` | `true` | `LiteflowConfig.java:32` |
| `ruleSource` | `liteflow.rule-source` | —（文件／传统 SPI 规则源时配置；纯动态构造与 Rule-DB 模式可空） | `:35` |
| `ruleSourceExtData` / `ruleSourceExtDataMap` | `liteflow.rule-source-ext-data{}` | — | `:38` / `:40` |
| `slotSize` | `liteflow.slot-size` | `1024` | `:43` |
| `whenMaxWaitSeconds` | `liteflow.when-max-wait-seconds` | — | `:47` |
| `whenMaxWaitTime` | `liteflow.when-max-wait-time` | `15000` | `:49` |
| `whenMaxWaitTimeUnit` | `liteflow.when-max-wait-time-unit` | `MILLISECONDS` | `:51` |
| `whenThreadPoolIsolate` | `liteflow.when-thread-pool-isolate` | `false` | `:54` |
| `enableLog` | `liteflow.monitor.enable-log` | `false` | `:57`（getter 在 null 时返回 `Boolean.FALSE`）；key 带 `monitor.` 前缀，源码无 `liteflow.enable-log` |
| `parseMode` | `liteflow.parse-mode` | `PARSE_ALL_ON_START` | `:73` |
| `supportMultipleType` | `liteflow.support-multiple-type` | `false` | `:77` |
| `retryCount` | `liteflow.retry-count` | `0` | `:81` |
| `nodeExecutorClass` | `liteflow.node-executor-class` | `DefaultNodeExecutor` | `:84` |
| `requestIdGeneratorClass` | `liteflow.request-id-generator-class` | `DefaultRequestIdGenerator` | `:87` |
| `mainExecutorWorks` | `liteflow.main-executor-works` | `64` | `:93` |
| `mainExecutorClass` | `liteflow.main-executor-class` | `LiteFlowDefaultMainExecutorBuilder` | `:96` |
| `printExecutionLog` | `liteflow.print-execution-log` | `true` | `:99` |
| `enableMonitorFile` | `liteflow.enable-monitor-file` | `false` | `:102` |
| `fallbackCmpEnable` | `liteflow.fallback-cmp-enable` | `false` | `:105` |
| `fastLoad` | `liteflow.fast-load` | `false` | `:108` |
| `enableNodeInstanceId` | `liteflow.enable-node-instance-id` | `false` | `:114` |
| `instanceIdGeneratorClass` | （无对应 `liteflow.*` key） | `DefaultRequestIdGenerator` | `:117`（getter 兜底；与 `requestIdGeneratorClass` 区分） |
| `chainCacheEnabled` | `liteflow.chain-cache.enabled` | `false` | `:120` |
| `chainCacheCapacity` | `liteflow.chain-cache.capacity` | `10000` | `:123` |
| `enableVirtualThread` | `liteflow.enable-virtual-thread` | `true` | `:126` |
| `globalThreadPoolExecutorClass` | `liteflow.global-thread-pool-executor-class` | `LiteFlowDefaultGlobalExecutorBuilder` | `:140` |
| `globalThreadPoolSize` | `liteflow.global-thread-pool-size` | `64` | `:143` |
| `globalThreadPoolQueueSize` | `liteflow.global-thread-pool-queue-size` | `512` | `:146` |

默认值来源（节选，`liteflow-spring-boot-starter/.../META-INF/liteflow-default.properties`）：

```properties
liteflow.slot-size=1024
liteflow.when-max-wait-time=15000
liteflow.parse-mode=PARSE_ALL_ON_START
liteflow.fast-load=false
liteflow.enable-monitor-file=false
liteflow.retry-count=0
```

> `slotSize` 经 `DataBus.init()` 读入（`DataBus.java:66`）；`parseMode` 在构造器分支判断（`FlowExecutor.java:87`）；`whenMaxWaitTime` 等用于 `WhenCondition` 的 `maxWaitTime/maxWaitTimeUnit` 字段（`WhenCondition.java`）；`fastLoad` 决定 `FlowBus` 集合类型（`FlowBus.java:79`）；`enableMonitorFile` 决定是否启动 `MonitorFile`（`FlowExecutor.java:228`）。

---

## 11. Rule-DB 运行时（v2.16.1）

> 本节行号对齐 **v2.16.1** 源码；`com.yomahub.liteflow.repository` 包整体为该版本新增（各类 javadoc 均标 `@since 2.16.1`）。

v2.16.1 引入 **Rule-DB 模式**：规则（chain EL / 脚本源码）存放在数据库等外部存储，core 通过仓储 SPI 拉取，替代本地文件等 `rule-source` 方式。两者**互斥**——`FlowExecutor.init` 检测到 rule-db 激活（classpath 存在 `RuleRepository` 实现且未显式关闭）时，若同时配置了 `ruleSource` 直接抛 `ConfigErrorException`，否则转入 rule-db 初始化并跳过常规解析（`liteflow-core/.../core/FlowExecutor.java:124-131`）。

### 11.1 包结构：`com.yomahub.liteflow.repository`

| 分组 | 类 | 职责 |
| --- | --- | --- |
| 仓储 SPI | `RuleRepository`（`repository/RuleRepository.java:16`） | 后端中立的权威读取接口：`fetchManifest()`（全量清单，仅 id+version+md5，不含内容）/ `fetchChain` / `fetchScript` |
| Provider | `RuleDbProvider` / `RuleDbProviderHolder` | provider 抽象（暴露 `repository()` / `changeSource()` / `type()`）与发现、持有 |
| 运行时核心 | `RuleDbRuntime`（`repository/RuleDbRuntime.java:54`） | 常驻版本戳索引 + 懒回源；`snapshot()`（`:953`）返回运行时快照（各状态计数 / 失败目标 / 变更源健康度） |
| 变更同步 | `RuleDbSyncManager`（`repository/RuleDbSyncManager.java:28`） | 变更投递串行化 + 周期 manifest 对账（`startReconcileScheduler` 在 `:127`，默认 60 秒见 `:131-133`） |
| 有界缓存 | `RuleDbCache`（`repository/RuleDbCache.java:26`） | 基于 Caffeine 的有界缓存（容量按 chain 条数，默认 500）；淘汰 chain 时其引用脚本的计数 -1，归零则卸载脚本 |
| 变更通道 | `RuleChangeSource` / `ManualPollingChangeSource` / `RuleChangeListener` / `ChangeSourceHealth` | 变更订阅 / 手动轮询抽象与回调；健康度四态 `STARTING/UP/DEGRADED/DOWN`（`ChangeSourceHealth.java:6-11`） |
| 目标状态机 | `runtime/RuleTargetState` / `runtime/RuleTargetStatus` | 每个 chain/script 的目标态：`SHADOW/READY/STALE/LOADING/FAILED/DELETED`（`runtime/RuleTargetStatus.java:4-12`） |
| 候选装载 | `runtime/ChainCandidateLoader` / `runtime/ScriptCandidateLoader` | 在总线之外构建候选，编译成功才安装（install），失败不污染在役版本 |
| 值对象 | `vo/ChainRecord` / `ScriptRecord` / `ChainMeta` / `ScriptMeta` / `RuleManifest` / `ChangeRecord` / `RuleDbRuntimeSnapshot` | 规则记录 / 元数据 / 清单 / 变更记录 / 快照 |

配置挂在 `LiteflowConfig.ruleDb`：`RuleDbConfig` 聚合 `RuleDbCacheConfig`（容量／预加载）、`RuleDbSyncConfig`（轮询、对账、`fetch-retry-times`）以及 `RuleDbSqlConfig` / `RuleDbPostgresqlConfig` / `RuleDbMongoConfig` / `RuleDbRedisConfig` / `RuleDbZkConfig` / `RuleDbEtcdConfig` / `RuleDbNacosConfig`。

### 11.2 启动：拉 manifest + 注册影子

`FlowExecutor.init` 的 rule-db 分支调用 `RuleDbRuntime.init()`（`RuleDbRuntime.java:169-218`）：

1. 先 `RuleDbSyncManager.open(provider)` 打开变更源（`:181`）——拉快照期间到达的变更事件会被缓冲，等基线确定后回放；
2. `fetchManifest()` 拉全量清单（`:183`）并校验；
3. 按清单注册 **chain 影子**与 **script 影子**（`:188-198`）——只有元数据（id/version/md5/type/language），无 EL / 脚本正文，`isCompiled=false`；
4. 初始化有界缓存（`:201-207`），以 manifest 的 `latestSeq` 为基线激活变更源（`:210`），启动周期对账（`:211`），按配置预加载（`:212`）；
5. 任一步失败：`stop` + 清理运行时状态后原样抛出（`:213-217`）——**启动即报错**，不带病运行。

### 11.3 执行热路径：本地命中 + 懒回源

`FlowBus.getChain(chainId)` 是纯本地查找（见第 2 节），已编译的 chain 直接执行——**热路径零远程调用**。只有影子 / 失效的 chain 才回源：

- `Chain.execute` 先走 `ensureCompiled()`（调用点在 `Chain.java:132`，方法体 `:213-235`）：若 `RuleDbRuntime.isChainStale(chainId)` 为 true（已被失效），或"未编译且为 rule-db 管理"（影子），直接 `buildUnCompileChain` 回源（`:214-218`）；其余情况走双检锁（`synchronized(this)` 双检在 `:224-231`），且 rule-db 的回源编译刻意放到 **monitor 之外**执行（`:232-234`），避免长时持锁阻塞并发执行。
- 回源钩子：`LiteFlowChainELBuilder.buildUnCompileChain` 编译前调 `RuleDbRuntime.ensureChainLoaded(chainId)`（`RuleDbRuntime.java:382`）按 id 拉 EL 正文填入 chain；拉取按 `fetch-retry-times` 重试（默认 3 次，`retryTimes()` 在 `:758-762`，`fetchChainWithRetry` 在 `:702`）。
- 脚本同理：`FlowBus` 编译脚本节点时，rule-db 管理的节点先 `RuleDbRuntime.ensureScriptLoaded(node)` 拉脚本源码（`FlowBus.java:281-282`，钩子本体在 `RuleDbRuntime.java:439`）。
- 编译成功后写缓存并登记脚本引用计数（`recordChainCache`，`RuleDbRuntime.java:821-832`）。

### 11.4 一致性：失效驱动 + copy-on-write

- 变更经 `RuleChangeSource` 到达 → `RuleDbSyncManager.applyChanges`（`:196`）按 seq 排序并做连续性校验（`:228-229`）；发现 seq 缺口（gap）则放弃增量、改为触发全量 manifest 对账；
- 变更只把对应 `RuleTargetState` 置为 `STALE`——**置失效，不就地替换**；下次执行经 `ensureCompiled` 懒回源拿新版本；
- 进行中的执行不受影响：`Chain.execute` 执行前已把 `conditionList` 引用拷到局部变量（见 9.3 节），持旧引用跑完，即 copy-on-write；
- 周期对账兜底（默认 60 秒，`RuleDbSyncManager.java:131-137`），并汇总变更源健康度（`changeSourceHealth()` 在 `:374`）。

### 11.5 `ChainLoadException` vs `ChainNotFoundException`

`ChainLoadException`（`exception/ChainLoadException.java:9`，`@since 2.16.1`）表示 **Rule-DB 模式下回源加载失败**——按 javadoc 的界定是"规则存在但取不回来"（重试耗尽、加载期间被变更 / 删除等均属此类）；rule-db 模式下"仓储中不存在或已停用"也归入它（`RuleDbRuntime.java:396-398`）。而 `ChainNotFoundException` 是常规模式下 `chainMap` 里根本没有该 chain。排查方向：前者看存储连通性与对账日志，后者看规则是否注册。

---

## 附：核心调用链一览

执行一次 `execute2Resp(chainId, param, ctxClass)`：

```
FlowExecutor.execute2Resp(...)                 (FlowExecutor.java:264/506)
  └─ doExecute(...)                            (FlowExecutor.java:535)
       ├─ DataBus.offerSlotByClass/Bean(...)   (DataBus.java:75/85 → offerIndex :102)
       ├─ FlowBus.getChain(chainId)            (FlowBus.java:91)
       ├─ chain.execute(slotIndex)             (Chain.java:116)
       │    └─ (未编译则 buildUnCompileChain)   (Chain.java:124)
       │    └─ for condition : conditionList
       │         condition.execute(slotIndex)  (Condition.execute)
       │              └─ executeCondition(...)  (各子类: Then/When/If/Switch/For/...)
       │                   └─ node.execute()    (NodeComponent.java:95)
       │                        ├─ beforeProcess / process / onSuccess
       │                        └─ onError(异常) / afterProcess(finally)
       ├─ (异常) 逆序 rollback                   (FlowExecutor.java:613-638)
       └─ DataBus.releaseSlot(slotIndex)        (DataBus.java:150, 在 finally)
```

## 12. Agent 2.16.2 源码路径与运行链

AgentScope 业务入口是 core 模块内的 `HarnessAgentComponent`。Jev 入口为独立模块中的 `JevSwitchComponent`，详见 [agent-jev.md](agent-jev.md)。下面的路径均相对 LiteFlow 仓库，不依赖开发机器绝对路径：

| 关注点 | 源码 |
|---|---|
| 配置及默认值 | `liteflow-core/src/main/java/com/yomahub/liteflow/property/agent/AgentConfig.java` 与相邻子配置 |
| 通用执行／身份／关闭 | `liteflow-agent/liteflow-agent-core/src/main/java/com/yomahub/liteflow/agent/component/AbstractAgentComponent.java` |
| 模型／工具／MCP／技能装配 | 同模块 `agent/component/AbstractAgentScopeComponent.java` |
| Harness 及自适应压缩装配 | 同模块 `agent/harness/component/HarnessAgentComponent.java` |
| 身份合法性 | 同模块 `agent/context/AgentInvocationIdentity.java` |
| 会话守卫选择 | 同模块 `agent/guard/AgentInvocationGuardResolver.java` |
| 展示历史与删除 | 同模块 `agent/conversation/AgentConversationService.java` |
| 事件协议 | 同模块 `agent/event/AgentEventTypeMapper.java` |
| 执行副本与持久文件 | 同模块 `agent/harness/storage/` 和 `agent/harness/filesystem/` |
| Docker 缓存与恢复 | 同模块 `agent/harness/sandbox/SessionSandboxRegistry.java` |
| A2A 客户端 | `liteflow-agent/liteflow-agent-a2a/src/main/java/com/yomahub/liteflow/agent/a2a/A2aAgentComponent.java` |
| Jev 选择与 HTTP 协议 | `liteflow-agent/liteflow-agent-jev/src/main/java/com/yomahub/liteflow/agent/jev/` 下的 `JevSwitchComponent`、`JevChoiceClient`、`JevChoiceResult`、`JevInvocationException` |
| Jev 配置、provider 与默认值 | `liteflow-core/src/main/java/com/yomahub/liteflow/property/agent/` 下的 `JevConfig.java`、`JevProvider.java`；后者定义 TypeSafe／OpenRouter 的默认地址、模型与接口路径 |

调用顺序：`FlowExecutor` 分配 Slot → `AbstractAgentComponent.process()` 校验配置并解析 conversationId／agentKey → 取得 Agent 与工作区租约 → 惰性构建 Runtime → 创建带执行 deadline 的 LiteFlowAgentContext → 生成输入并调用 Harness → 事件／工具／可能的审批 → `handleReply` 写 responseData → 清理上下文、释放租约。

deadline 在取锁和首次构建之后建立，因此 execution-timeout 不包含它们。模型、工具和仓库大多在构建期绑定，请求内容放 userPrompt／transformSystemPrompt／RuntimeContext。相同会话跨 Agent 共享文件，因此工作区锁可能使 WHEN 中的不同 Agent 排队。历史与模型状态分别持久化，源码查询不要再寻找旧 AgentComponent、独立 harness Maven 模块或 userId 四元组。
