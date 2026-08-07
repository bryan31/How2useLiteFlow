> 来源文档（相对 `04.v2.16.X文档/`）：
> - `060.🔗组件/010.🛍继承式组件/010.普通组件.md`
> - `060.🔗组件/010.🛍继承式组件/020.选择组件.md`
> - `060.🔗组件/010.🛍继承式组件/030.布尔组件.md`
> - `060.🔗组件/010.🛍继承式组件/040.次数循环组件.md`
> - `060.🔗组件/010.🛍继承式组件/055.迭代循环组件.md`
> - `060.🔗组件/010.🛍继承式组件/060.LiteflowComponent.md`
> - `060.🔗组件/010.🛍继承式组件/070.组件内方法覆盖和调用.md`
> - `060.🔗组件/020.🎁声明式组件/010.什么叫声明式组件.md`
> - `060.🔗组件/020.🎁声明式组件/020.类级别式声明.md`
> - `060.🔗组件/020.🎁声明式组件/030.方法级别式声明.md`
>
> 版本对齐：LiteFlow **v2.16.X**。类名/方法名/枚举值已与 `liteflow-core` 源码核对一致。

# LiteFlow 组件参考

LiteFlow 节点（组件）是编排的最小执行单元。每种组件由一个基类 + 一个必须实现的 `process*` 方法定义，并在 EL 中对应特定的编排关键字。本文覆盖两大写法：

- **继承式**：自定义类继承 `NodeComponent` 等基类（源码包 `com.yomahub.liteflow.core`）。
- **声明式**：普通 Spring Bean + 注解，不继承任何基类（SpringBoot 与 Solon 环境可用）。

所有组件均为 Spring Bean，可用 `@Autowired` / `@Resource` 注入其它 Bean。

---

## 一、继承式组件

### 1. 普通组件 `NodeComponent`

最常用的组件，可用于 `THEN`、`WHEN` 等。必须实现 `process()`。

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        System.out.println("ACmp executed!");
    }
}
```

配套 EL：

```xml
<chain name="chain1">
    THEN(a, b);
</chain>
```

### 2. 选择组件 `NodeSwitchComponent`

用于 `SWITCH`。必须实现 `processSwitch()`，返回 `String`，即下一跳的 `nodeId`。

```java
@LiteflowComponent("a")
public class ACmp extends NodeSwitchComponent {
    @Override
    public String processSwitch() throws Exception {
        return "c";   // 进入 nodeId 为 c 的节点
    }
}
```

配套 EL 与返回值约定：

```xml
<chain name="chain1">
    SWITCH(a).to(b, c);
</chain>
```

`processSwitch` 返回值支持多种形式（以下文档原文给出的语义）：

| 返回值写法 | 含义 |
|---|---|
| `"c"` | 选择 `targetId` 为 `c` 的节点 |
| `"w1"` | 当目标表达式标了 `.id("w1")` 时，选择该表达式 |
| `"tag:dog"` / `":dog"` | 选择第一个标签为 `dog` 的节点 |
| `"b:td"` | 选择 `targetId=b` 且标签=`td` 的节点 |
| `"b:"` | 选择第一个 `targetId=b` 的节点 |
| `":"` | 选择第一个节点 |
| `"b:x"` | **报错**（反例：没有 `targetId=b` 且标签=`x` 的节点） |
| `"x"` | **报错**（反例：没有 `targetId=x` 的节点） |
| `"::"` | **报错**（反例：找不到标签为 `:` 的节点） |

**返回值无命中时的运行期行为**（源码 `SwitchCondition.java:70-90`）：`processSwitch` 返回值未命中任何目标时，若 EL 配了 `SWITCH(x).TO(a, b, c).DEFAULT(y)`（`DEFAULT` 关键字 v2.9.5+，里面也可以是表达式）则走 `DEFAULT` 分支；连 `DEFAULT` 也没配则抛 `NoSwitchTargetNodeException`（`com.yomahub.liteflow.exception` 包，报错信息形如 `[requestId]:no target node find for the component[xxx],target str is [yyy]`）。该异常被 Chain 层捕获后整个流程失败（`response.isSuccess()=false`），因此返回值集合不确定时建议配 `DEFAULT` 兜底。

- 表达式也可用 `.tag("w1")`，返回 `tag:w1` 或 `:w1` 即可命中（v2.10.2+）。
- 链路同样支持 tag：`SWITCH(a).to(b, sub.tag("w1"))`，返回 `sub` 或 `tag:w1` 都能命中（v2.10.3+）。
- v2.15.0+ 起可在选择组件内 `this.getTargetList()`（返回 `List<String>`）拿到当前目标节点 id 列表。

### 3. 布尔组件 `NodeBooleanComponent`（v2.12.0+）

返回 `boolean`，是 `IF` / `WHILE` / `BREAK` 三类组件的统一形态。必须实现 `processBoolean()`。

```java
@LiteflowComponent("x")
public class XCmp extends NodeBooleanComponent {
    @Override
    public boolean processBoolean() throws Exception {
        return true;
    }
}
```

配套 EL：

```xml
<!-- 条件 -->
<chain name="c1">
    IF(x, THEN(a, b));
    IF(x, a).ELIF(y, b).ELSE(c);
</chain>

<!-- 循环条件 / 中断 -->
<chain name="c2">
    WHILE(x).DO(a);
    FOR(f).DO(a).BREAK(x);
</chain>
```

### 4. 次数循环组件 `NodeForComponent`（v2.9.0+）

用于 `FOR...DO...`。必须实现 `processFor()`，返回 `int`（循环次数）。

```java
@LiteflowComponent("f")
public class FCmp extends NodeForComponent {
    @Override
    public int processFor() throws Exception {
        return 10;  // DO 块执行 10 次
    }
}
```

配套 EL：

```xml
<chain name="chain1">
    FOR(f).DO(THEN(a, b));
</chain>
```

`DO` 内任意组件可通过 `this.getLoopIndex()` 拿到当前层下标；脚本中用 `_meta.loopIndex`。

### 5. 迭代循环组件 `NodeIteratorComponent`（v2.9.7+）

用于 `ITERATOR...DO...`，相当于 Java 的 `Iterator`。必须实现 `processIterator()`，返回 `Iterator<?>`。

```java
@LiteflowComponent("x")
public class XCmp extends NodeIteratorComponent {
    @Override
    public Iterator<?> processIterator() throws Exception {
        List<String> list = ListUtil.toList("jack", "mary", "tom");
        return list.iterator();
    }
}
```

配套 EL：

```xml
<chain name="chain1">
    ITERATOR(x).DO(THEN(a, b));
</chain>
```

`DO` 内任意组件可通过 `this.getCurrLoopObj()` 拿到当前迭代对象；脚本中用 `_meta.loopObject`。

### 多层嵌套循环下标/对象获取（v2.12.3+）

`FOR` 与 `ITERATOR` 均适用，以 3 层嵌套为例：

| 取哪一层 | FOR（下标） | ITERATOR（对象） |
|---|---|---|
| 当前层 | `getLoopIndex()` 或 `getPreNLoopIndex(0)` | `getCurrLoopObj()` 或 `getPreNLoopObj(0)` |
| 上一层 | `getPreLoopIndex()` 或 `getPreNLoopIndex(1)` | `getPreLoopObj()` 或 `getPreNLoopObj(1)` |
| 上上层 | `getPreNLoopIndex(2)` | `getPreNLoopObj(2)` |

`getPreNLoopXxx(n)` 的 `n` 表示**往前**取多少层，`0` 即当前层。

---

## 二、`@LiteflowComponent` 与 nodeId 规则

`@LiteflowComponent` 继承自 Spring `@Component`，额外提供 `name` 属性用于给组件起别名（在打印调用链时体现）。新版本推荐使用 `@LiteflowComponent`，`@Component` 仍兼容。

```java
// value = nodeId；name = 别名（打印链路用）
@LiteflowComponent(value = "a", name = "A组件")
```

**nodeId 命名约束**（违反会在编排时编译不过）：

- 不能以数字开头（如 `88Cmp` 非法）。
- 中间不能出现运算符号（如 `cmp-11`、`user=123` 非法）。

> 打破该限制需用「组件名包装」机制（以源码/官方文档为准，本文件不展开）。

---

## 三、组件内可覆盖的方法（生命周期钩子）

继承式组件可在子类覆盖以下方法（声明式组件用同名 `LiteFlowMethodEnum` 映射，见下节）。源码位置 `NodeComponent.java`。

| 方法签名 | 触发时机 / 用途 | 返回值含义 |
|---|---|---|
| `boolean isAccess()` | 是否进入该节点，用于业务参数预判断；在 `beforeProcess` **之前**执行 | `true` 进入，`false` 跳过本节点 |
| `void beforeProcess()` | 前置处理器（在 `isAccess` 之后执行） | 无返回值 |
| `void afterProcess()` | 后置处理器 | 无返回值 |
| `void onSuccess()` | 流程成功事件回调 | 无返回值 |
| `void onError(Exception e)` | 流程失败事件回调 | 无返回值 |
| `boolean isContinueOnError()` | 出错是否继续往下执行下一个组件，**默认 false** | `true` 继续，`false` 中断 |
| `boolean isEnd()` | 执行完本节点后是否终止**整个流程** | `true` 终止（属用户主动结束，`isSuccess` 仍为 `true`） |
| `void rollback()` | 流程失败后的回滚方法 | 无返回值 |

> 统一的组件前后置处理，文档推荐用「组件切面」而非 `beforeProcess/afterProcess`。

关于 `isEnd` / `setIsEnd(true)` 与 `isContinueOnError` 的交互（文档 tip 原文）：即便 `isContinueOnError=true`，若调用了 `this.setIsEnd(true)`，流程依旧终止，且 `response.isSuccess` 仍为 `true`。

### `this` 关键字可调用的方法

| 方法 | 作用 |
|---|---|
| `<T> T getContextBean(Class<T>)` | 获取当前自定义上下文，进而取任意数据 |
| `String getNodeId()` | 组件 ID |
| `String getName()` | 组件别名 |
| `String getChainId()` | 最外层流程名（嵌套时只取最外层） |
| `String getCurrChainId()` | 当前组件所在链路名（chain1 调用 chain2，链路内组件取到 chain2） |
| `getRequestData()` | 流程初始参数 |
| `void setIsEnd(true)` | 立即结束整个流程（正常结束，`isSuccess=true`） |
| `String getTag()` | 组件标签 |
| `invoke2Resp(...)` | 调用隐式子流程（源码方法名为 `invoke2Resp`，**无** `invoke` / `invoke2Response`） |
| `<T> T getBindData(String key, Class<T> clazz)` / `getBindDataList(String key, Class<T> clazz)` | v2.13.0+，获得 `bind` 绑定的数据（**无无参版本**，`this.getBindData()` 编译不过） |

---

## 四、声明式组件

让普通 Java Bean 不继承任何基类、仅靠注解成为 LiteFlow 组件。**SpringBoot 与 Solon 环境可用**（v2.16.X 下 Solon 已支持，见 `SolonDeclComponentParser` 与测试模块 `liteflow-testcase-el-declare-multi-solon`；纯 Spring XML / 非 Spring 环境不支持）。

### 1. 类级别式声明

一个类 = 一个组件。方法上用 `@LiteflowMethod(value=..., nodeType=...)` 把自定义方法映射成组件方法。

```java
@LiteflowComponent("a")
public class ACmp {

    @LiteflowMethod(LiteFlowMethodEnum.PROCESS, nodeType = NodeTypeEnum.COMMON)
    public void processAcmp(NodeComponent bindCmp) {
        System.out.println("ACmp executed!");
    }

    @LiteflowMethod(LiteFlowMethodEnum.IS_ACCESS, nodeType = NodeTypeEnum.COMMON)
    public boolean isAcmpAccess(NodeComponent bindCmp) { return true; }

    @LiteflowMethod(LiteFlowMethodEnum.BEFORE_PROCESS, nodeType = NodeTypeEnum.COMMON)
    public void beforeAcmp(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(LiteFlowMethodEnum.AFTER_PROCESS, nodeType = NodeTypeEnum.COMMON)
    public void afterAcmp(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(LiteFlowMethodEnum.ON_SUCCESS, nodeType = NodeTypeEnum.COMMON)
    public void onAcmpSuccess(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(LiteFlowMethodEnum.ON_ERROR, nodeType = NodeTypeEnum.COMMON)
    public void onAcmpError(NodeComponent bindCmp, Exception e) { /* ... */ }

    @LiteflowMethod(LiteFlowMethodEnum.IS_END, nodeType = NodeTypeEnum.COMMON)
    public boolean isAcmpEnd(NodeComponent bindCmp) { return false; }

    @LiteflowMethod(value = LiteFlowMethodEnum.ROLLBACK, nodeType = NodeTypeEnum.COMMON)
    public void rollbackA(NodeComponent bindCmp) { /* ... */ }
}
```

各组件类型只需改 `LiteFlowMethodEnum` 与 `NodeTypeEnum`：

| 组件 | `LiteFlowMethodEnum` | `NodeTypeEnum` | 方法返回值 |
|---|---|---|---|
| 普通 | `PROCESS` | `COMMON` | `void` |
| 选择 | `PROCESS_SWITCH` | `SWITCH` | `String` |
| 布尔 | `PROCESS_BOOLEAN` | `BOOLEAN` | `boolean` |
| 次数循环 | `PROCESS_FOR` | `FOR` | `int` |
| 迭代循环 | `PROCESS_ITERATOR` | `ITERATOR` | `Iterator<?>` |

**类级别式声明的硬性规则（文档原文）：**

- 方法名随意，不起决定作用；方法性质由 `@LiteflowMethod` 的 `LiteFlowMethodEnum` 决定。
- 方法**第一个参数必须是** `NodeComponent bindCmp`。
- 原本有参数的钩子，追加在 `bindCmp` 之后，例如 `onError` 写成 `yourName(NodeComponent bindCmp, Exception e)`。
- 原本用 `this` 调用的，改用 `bindCmp` 调用。
- **返回值必须与继承式一致**（布尔返回 `boolean`、选择返回 `String`、次数循环返回 `int`…），写错会增加排查时间。

#### nodeType 的两种声明方式（都合法）

上面示例把 `nodeType` 写在每个 `@LiteflowMethod` 上（官方文档主线写法）。源码里还支持**在类上**用 `@LiteflowCmpDefine(类型)` 统一声明节点类型——这两种等价，按喜好二选一：

```java
// 写法 B：类上用 @LiteflowCmpDefine 声明 nodeType（源码测试用例常见写法）
@LiteflowComponent("w")            // 注册 nodeId（不能省，@LiteflowCmpDefine 不负责注册）
@LiteflowCmpDefine(NodeTypeEnum.BOOLEAN)
public class WCmp {
    @LiteflowMethod(LiteFlowMethodEnum.PROCESS_BOOLEAN)   // 此处可不再写 nodeType
    public boolean processWhile(NodeComponent bindCmp) { return true; }
}
```

规则（源码 `SpringDeclComponentParser` / `SolonDeclComponentParser`）：
- **注册 nodeId 始终靠 `@LiteflowComponent`/`@Component`**；`@LiteflowCmpDefine` 只有 `NodeTypeEnum value()`、**不能注册组件**。
- nodeType 解析优先级：**类上有 `@LiteflowCmpDefine` 就用它的值**（此时 `@LiteflowMethod(nodeType=...)` 被忽略）；没有才回退到 `@LiteflowMethod.nodeType()`（默认 `COMMON`）。

### 2. 方法级别式声明（v2.9.0+）

一个类里通过注解定义**多个**组件——适合组件数量多、想减少类定义的场景。与类级别相比，`@LiteflowMethod` 多了 `nodeId`（可选 `nodeName`）参数，同组件的多个方法标相同 `nodeId` 即归为一组。

```java
@LiteflowComponent
public class CmpConfig {

    // 普通组件 a
    @LiteflowMethod(value = LiteFlowMethodEnum.PROCESS, nodeId = "a", nodeType = NodeTypeEnum.COMMON)
    public void processA(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(value = LiteFlowMethodEnum.IS_ACCESS, nodeId = "a", nodeType = NodeTypeEnum.COMMON)
    public boolean isAccessA(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(value = LiteFlowMethodEnum.ON_SUCCESS, nodeId = "a", nodeType = NodeTypeEnum.COMMON)
    public void onSuccessA(NodeComponent bindCmp) { /* ... */ }

    // 布尔组件 f
    @LiteflowMethod(value = LiteFlowMethodEnum.PROCESS_BOOLEAN, nodeId = "f", nodeType = NodeTypeEnum.BOOLEAN)
    public boolean processF(NodeComponent bindCmp) { /* ... */ }

    @LiteflowMethod(value = LiteFlowMethodEnum.IS_ACCESS, nodeId = "f", nodeType = NodeTypeEnum.BOOLEAN)
    public boolean isAccessF(NodeComponent bindCmp) { /* ... */ }
}
```

其余规则与类级别式声明一致。

---

## 五、行为对照表

| 你要实现的行为 | 继承式 | 声明式 | 关联 EL |
|---|---|---|---|
| 顺序/并行执行一段逻辑 | `NodeComponent` + `process()` | `PROCESS` + `COMMON` | `THEN` / `WHEN` |
| 动态决定下一跳节点 | `NodeSwitchComponent` + `processSwitch()` 返回 `String` | `PROCESS_SWITCH` + `SWITCH` | `SWITCH...to(...)` |
| IF/WHILE/BREAK 的条件判断 | `NodeBooleanComponent` + `processBoolean()` 返回 `boolean` | `PROCESS_BOOLEAN` + `BOOLEAN` | `IF` / `WHILE` / `BREAK` |
| 固定次数循环 | `NodeForComponent` + `processFor()` 返回 `int` | `PROCESS_FOR` + `FOR` | `FOR...DO...` |
| 集合迭代循环 | `NodeIteratorComponent` + `processIterator()` 返回 `Iterator<?>` | `PROCESS_ITERATOR` + `ITERATOR` | `ITERATOR...DO...` |
| 进入节点前的参数预判 | 覆盖 `isAccess()` | `IS_ACCESS` | — |
| 节点前后置处理 | 覆盖 `beforeProcess()` / `afterProcess()` | `BEFORE_PROCESS` / `AFTER_PROCESS` | — |
| 成功/失败回调 | 覆盖 `onSuccess()` / `onError(Exception)` | `ON_SUCCESS` / `ON_ERROR` | — |
| 出错后是否继续下一个组件 | 覆盖 `isContinueOnError()`（默认 `false`） | `IS_CONTINUE_ON_ERROR` | — |
| 执行完本节点终止整个流程 | 覆盖 `isEnd()` 或 `this.setIsEnd(true)` | `IS_END` | — |
| 失败后回滚 | 覆盖 `rollback()` | `ROLLBACK` | — |
| 取循环下标 / 迭代对象 | `getLoopIndex()` / `getCurrLoopObj()` 等 | 同（通过 `bindCmp` 调用） | `FOR` / `ITERATOR` 的 `DO` 内 |
| 选择组件看候选节点 | `this.getTargetList()`（`List<String>`，v2.15.0+） | 通过 `bindCmp` 调用 | `SWITCH` |

---

## 六、常见坑 / 注意

- **nodeId 非法命名**：不能以数字开头，中间不能有运算符号（`88Cmp`、`cmp-11`、`user=123` 均会编译不过）。打破限制需用「组件名包装」（以源码/官方文档为准）。
- **声明式组件**在 SpringBoot 与 Solon 环境可用；纯 Spring XML / 非 Spring 环境不支持（早期文档称"仅 SpringBoot"，v2.16.X 起 Solon 也支持）。
- **声明式方法的返回值类型必须与继承式严格一致**（布尔返 `boolean`、选择返 `String`、次数循环返 `int`、迭代循环返 `Iterator<?>`），不一致会排查很久。
- **声明式方法的第一个参数必须是 `NodeComponent bindCmp`**；原本带参的钩子（如 `onError`）把额外参数放在 `bindCmp` 之后。
- **`isContinueOnError` 默认 `false`**——不覆盖时出错会中断后续组件。
- **`isEnd` / `setIsEnd(true)` 属用户主动结束**，`response.isSuccess` 仍为 `true`；即便 `isContinueOnError=true`，调用 `setIsEnd(true)` 依旧终止，且 `isSuccess` 仍为 `true`。
- **`getChainId` vs `getCurrChainId`**：嵌套链路里前者只取最外层 chain，后者取当前组件所在的链路。
- **多循环下标/对象取层**：`getPreNLoopIndex(n)` / `getPreNLoopObj(n)` 的 `n` 表示往前取多少层，`0` 是当前层（v2.12.3+）。
- 声明式里原本用 `this` 的能力，全部改用 `bindCmp` 调用。
