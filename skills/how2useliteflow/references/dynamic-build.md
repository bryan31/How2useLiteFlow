> 来源：官方文档 `docs/04.v2.16.X文档/130.🎲动态构造/`（010.说明 / 020.构造Node / 030.构造EL / 040.构造Chain），对齐 LiteFlow v2.16.X。
> 类名/方法名已与源码核对：`LiteFlowNodeBuilder`、`ELBus`、`LiteFlowChainELBuilder` 均真实存在（分别在 `liteflow-core` 与 `liteflow-el-builder` 模块）。

# 动态构造（Node / EL / Chain）


## 何时用动态构造

规则文件（xml/json/yaml）适合在项目启动时就确定的流程；而**动态构造**让你用 Java 代码在运行期新增/替换一条链路。典型场景：规则依赖运行时数据、规则按租户/灰度动态生成、脚本节点或代理类节点无法用静态 `@LiteflowComponent` 注册。

要点：

- 动态构造与规则配置**不冲突**，可单独用，也可混用（规则文件底层本身就是构造模式）。
- 支持**平滑热刷新**——高并发下运行期替换链路不会造成执行错乱。
- **不要每次执行都构造**。建议在初始化阶段构造一次；运行期需要替换时再重新构造，而不是每次 `invoke` 前都 build。

## 用 `LiteFlowNodeBuilder` 动态构造 Node

入口类 `com.yomahub.liteflow.builder.LiteFlowNodeBuilder`（位于 `liteflow-core`）。在 Spring/SpringBoot 环境里，标了 `@Component`/`@LiteflowComponent` 并被扫描的组件会自动注册，通常无需手动构造。手动构造主要面向：动态代理类、脚本节点、运行时才知道的类。

### 工厂方法（源码实测存在的全部入口）

| 方法 | 节点类型 |
| --- | --- |
| `createNode()` | 不指定类型（需后续 `setType`） |
| `createCommonNode()` | 普通组件 |
| `createSwitchNode()` | 选择组件 |
| `createBooleanNode()` | 布尔组件（IF/WHILE/AND/OR/NOT 用） |
| `createForNode()` | 次数循环组件 |
| `createIteratorNode()` | 迭代循环组件 |
| `createScriptNode()` | 普通脚本组件 |
| `createScriptSwitchNode()` | 脚本选择组件 |
| `createScriptBooleanNode()` | 脚本布尔组件 |
| `createScriptForNode()` | 脚本次数循环组件 |

链式 setter（均返回 `LiteFlowNodeBuilder`）：`setId(String)`、`setName(String)`、`setClazz(String)` 或 `setClazz(Class<?>)`、`setType(NodeTypeEnum)`、`setScript(String)`、`setFile(String)`（从文件载入脚本，并登记其监听路径）、`setLanguage(String)`（脚本语言）。最后调 `build()` 注册到 `FlowBus`（普通节点走 `FlowBus.addNode`，脚本节点走 `FlowBus.addScriptNode`）。

`build()` 前会校验 `id` 非空、`type` 非空，不满足抛 `NodeBuildException`。

### 示例：注册普通组件、脚本组件、文件脚本组件

```java
// 普通组件：给出全限定类名
LiteFlowNodeBuilder.createCommonNode()
        .setId("a")
        .setName("组件A")
        .setClazz("com.yomahub.liteflow.test.builder.cmp.ACmp")
        .build();

// 选择组件
LiteFlowNodeBuilder.createSwitchNode()
        .setId("sw")
        .setName("选择组件")
        .setClazz("com.yomahub.liteflow.test.builder.cmp.SwitchCmp")
        .build();

// 普通脚本组件：直接内联脚本
LiteFlowNodeBuilder.createScriptNode()
        .setId("s1")
        .setName("脚本A")
        .setLanguage("groovy")
        .setScript("你的脚本内容")
        .build();

// 脚本选择组件
LiteFlowNodeBuilder.createScriptSwitchNode()
        .setId("ss1")
        .setName("脚本选择")
        .setLanguage("groovy")
        .setScript("你的脚本内容")
        .build();

// 从文件载入脚本；热刷新还要求启用文件监听，且 MonitorFile 已完成初始化
LiteFlowNodeBuilder.createScriptNode()
        .setId("s2")
        .setName("文件脚本")
        .setLanguage("groovy")
        .setFile("xml-script-file/s1.groovy")
        .build();
```

> `setFile` 本身只读取文件并把路径登记到 `MonitorFile`，并不负责创建 watcher。要让后续文件改动触发热刷新，还需设置 `liteflow.enable-monitor-file=true`，并确保文件监听器已经在 `FlowExecutor` 初始化阶段创建；若运行期才动态登记文件，应先确认 watcher 已初始化。
>
> 说明：手动构造的节点类**不需要**打 `@LiteflowComponent`/`@Component`；在 Spring 体系下，框架会把节点类注入 Spring 上下文，所以节点内部仍可用 `@Autowired`/`@Resource` 等 Spring 注解。

## 用 `ELBus` 在代码里拼 EL（不写 EL 字符串）

入口类 `com.yomahub.liteflow.builder.el.ELBus`（位于 `liteflow-el-builder` 模块，自 2.11.1 起提供）。每个工厂方法返回对应的 `*ELWrapper`，wrapper 上可继续链式调用子关键字方法（`tag`/`id`/`bind`/`any` 等），最后用 `toEL()` 输出单行 EL 字符串，或 `toEL(true)` 输出树形（便于人工校验）。

### 额外依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-el-builder</artifactId>
    <version>2.16.2</version>
</dependency>
```

> 注意：`LiteFlowChainELBuilder` 在 `liteflow-core` 里，动态拼 EL 的 `ELBus` 才在 `liteflow-el-builder` 里。只用字符串 EL 构造 Chain 不必引入此依赖；要用 `ELBus` 才需要。

### 基本用法：等价于 THEN/WHEN 嵌套

等价目标 EL：`THEN(a, WHEN(b, THEN(c, d)), e)`

```java
ThenELWrapper el = ELBus.then(
        "a",
        ELBus.when("b", ELBus.then("c", "d")),
        "e");
System.out.println(el.toEL());
// 输出：THEN(a,WHEN(b,THEN(c,d)),e)
```

要点：`ELBus.then("a")` 等价于 `ELBus.then(ELBus.element("a"))`——传 String 会被自动包装为普通节点 wrapper，区别是 `element(...)` 才能继续挂子关键字。

### 在表达式层挂子关键字（id / tag / bind / any …）

```java
// SWITCH(x).TO(WHEN(a,b).id("x1"), c)
String el1 = ELBus.switchOpt("x")
        .to(ELBus.when("a", "b").id("x1"), "c")
        .toEL();

// THEN(WHEN(a,b).any(true), c).bind("k1","v1")
String el2 = ELBus.then(ELBus.when("a", "b").any(true), "c")
        .bind("k1", "v1")
        .toEL();
```

### 在节点层挂子关键字（tag / bind / data）：`element` vs `node`

- `ELBus.element("a")` → 普通 `CommonNodeELWrapper`，可挂 `tag`/`bind`/`data` 等；生成的是裸组件名 `a`，加载时会校验节点存在、且组件名须符合命名规范。
- `ELBus.node("a")` → `NodeELWrapper`（继承 `CommonNodeELWrapper`，可挂的子关键字与 `element` 相同），额外给节点套上 `node(...)` 包装：加载时**不校验节点是否存在、也不校验命名规范**——节点不存在时生成 `FallbackNode` 代理而非报错（见 `NodeOperator.build`）。节点存在且命名合规时，`node("a")` 与裸写 `a` 等价。它的两个真实用途：
  1. **允许任意组件名**：数字开头、含运算符等违反命名规范的组件名（如 `node("88Cmp")`、`node("cmp-11")`）必须用 `node(...)` 包装（参见 el-rules 的"组件名包装"）。
  2. **组件降级的前提**：开启 `liteflow.fallback-cmp-enable=true` 后，只有被 `node(...)` 包装的缺失组件才会在运行期路由到 `@FallbackCmp` 降级组件；不加 `node` 的缺失组件在加载期直接报错，**不会**降级（参见 advanced 的"组件降级"）。

```java
// element：THEN(a.tag("t1"), b.bind("k1","v1"))
String el3 = ELBus.then(
        ELBus.element("a").tag("t1"),
        ELBus.element("b").bind("k1", "v1")
).toEL();

// node：THEN(node("a").tag("t1"), node("b").bind("k1","v1"))
String el4 = ELBus.then(
        ELBus.node("a").tag("t1"),
        ELBus.node("b").bind("k1", "v1")
).toEL();
```

### `ELBus` 支持的全部表达式入口（源码核对）

| EL | 工厂方法 | 后续方法（节选） |
| --- | --- | --- |
| 串行 THEN | `ELBus.then(...)` | `pre(...)`、`finallyOpt(...)`、`tag`、`id`、`maxWaitSeconds`、`data`、`bind`、`retry(...)` |
| 并行 WHEN | `ELBus.when(...)` | `any`、`percentage(...)`、`ignoreError`、`customThreadExecutor`、`must`、`tag`、`id`、`maxWaitSeconds`、`data`、`bind`、`retry(...)` |
| 选择 SWITCH | `ELBus.switchOpt(...)` | `to(...)`、`defaultOpt(...)`、`tag`、`id`、`maxWaitSeconds`、`data`、`bind`、`retry(...)` |
| 条件 IF | `ELBus.ifOpt(cond, trueEl[, falseEl])` | `elseOpt(...)`、`elIfOpt(...)`、`tag`、`id`、`maxWaitSeconds`、`data`、`bind`、`retry(...)` |
| 循环 | `ELBus.forOpt(...)`、`ELBus.whileOpt(...)`、`ELBus.iteratorOpt(...)` | `doOpt(...)`、`breakOpt(...)`、`parallel`、`tag`、`id`、`maxWaitSeconds`、`retry(...)` |
| 捕获异常 CATCH | `ELBus.catchException(...)` | `doOpt(...)`、`tag`、`id`、`maxWaitSeconds`、`data`、`bind`、`retry(...)` |
| 与 AND | `ELBus.and(...)` | 仅 `tag`、`id`（另有 `and(...)` 追加子表达式） |
| 或 OR | `ELBus.or(...)` | 仅 `tag`、`id`（另有 `or(...)` 追加子表达式） |
| 非 NOT | `ELBus.not(...)` | 仅 `tag`、`id` |
| 单节点 | `ELBus.node(...)` / `ELBus.element(...)` | `tag`、`data`、`maxWaitSeconds`、`bind`、`retry(...)` |

> 补充：`ELBus` 还提供 `ser(...)` / `par(...)` 入口，分别生成 `SER(...)` / `PAR(...)`。它们在语法和 wrapper 类型上独立，但运行语义分别等同于 `THEN(...)` / `WHEN(...)`，可视为串行与并行的语义别名。

> 注意（以源码为准，官方文档同名表格此处有误）：`AndELWrapper`/`OrELWrapper`/`NotELWrapper` 源码中只把 `tag`/`id` 覆写为 public；`data`/`bind`/`maxWaitSeconds`/`retry` 在父类 `ELWrapper` 上是 `protected` 且这三个子类未覆写，业务代码里对 AND/OR/NOT 链式调用这些方法会**直接编译报错**（这三个类的 Javadoc 虽写着"支持设置 id tag data maxWaitSeconds 属性"，实测并未提供对应 public 方法）。要给 AND/OR/NOT 表达式挂这些子关键字，只能手写 EL 文本。
>
> 版本：`retry(...)` 对应 EL 的 `.retry(3)` / `.retry(3, "异常类全限定名")`，v2.12.0+；`percentage(double)` 仅 WHEN 支持，v2.15.0+，取值 [0,1]（0 等价于 `any(true)`，1 等价于不加）。

### 树形输出便于校验

```java
WhenELWrapper el = ELBus.when("a",
        ELBus.when(ELBus.node("b")
                    .data("whenData", "{\"name\":\"zhangsan\",\"age\":18}"))
                .when("c")
                .id("this is a id"),
        "d")
        .tag("this is a tag")
        .any(true);
System.out.println(el.toEL(true));
```

`toEL(true)` 会输出带缩进的树形结构（含 `whenData = '...';` 这类 data 变量声明），便于人工核对复杂表达式。

### 参数类型校验

`ELBus` 在组装时会对参数类型做校验：

- `then`/`when` 等不接受 `AndELWrapper`/`OrELWrapper`/`NotELWrapper`（与或非表达式不能作为普通编排子项）。
- `and`/`or` 只接受可返回布尔值的参数（布尔节点或与或非表达式）。
- 例如 `WHILE(w).DO(THEN(a,b))` 中 `w` 必须是布尔节点或与或非表达式，否则组装期即报错。

更多用法可在 `liteflow-testcase-el/liteflow-testcase-el-builder` 测试模块查阅。

## 用 `LiteFlowChainELBuilder` 动态构造并注册 Chain

入口类 `com.yomahub.liteflow.builder.el.LiteFlowChainELBuilder`（位于 `liteflow-core`）。`build()` 时：chain 不存在则新增、存在则替换（修改），并最终通过 `FlowBus.addChain(...)` 注册。

### 字符串 EL 构造 Chain

```java
LiteFlowChainELBuilder.createChain()
        .setChainId("chain2")
        .setEL("THEN(a, b, WHEN(c, d))")
        .build();
```

> 源码提示：`setChainName(String)` 已标记 `@Deprecated`，新代码建议用 `setChainId(String)`（两者效果一致，均会判断 chain 是否已存在并复用已有 Chain 对象）。其它可选 setter：`setRoute(String routeEl)`（决策路由 EL）、`setNamespace(String)`、`setThreadPoolExecutorClass(String)`。

### 子流程依赖顺序

构造模式是**一条一条**添加 chain 的。在默认的立即解析模式下，如果 `chain1` 依赖（引用）`chain2`，必须**先构造 `chain2`**，否则解析时会因找不到被引用的 chain 而报错。`PARSE_ONE_ON_FIRST_EXEC` 会把解析推迟到首次执行，此时可以先注册主 chain，但仍须在第一次执行前注册完所有依赖。为兼容不同解析模式，通常都建议按“被依赖 chain 在前”的顺序构造；复杂局部逻辑也可用子变量拆分。

### 用 `ELBus` 动态拼 EL 再注册 Chain（推荐）

把 `ELBus` 拼出的表达式 `toEL()` 喂给 `setEL`，实现"代码即规则"：

```java
// 1. 用代码动态拼出等价 THEN(a, b, WHEN(c, d)) 的 EL
ELWrapper el = ELBus.then("a", "b", ELBus.when("c", "d"));

// 2. 用拼好的 EL 注册一个 chain
LiteFlowChainELBuilder.createChain()
        .setChainId("chain2")
        .setEL(el.toEL())
        .build();
```

### 等价对照速查（EL 字符串 ↔ 编程式）

| 目标语义 | EL 字符串 | 编程式（ELBus） |
| --- | --- | --- |
| 串行 | `THEN(a, b, c)` | `ELBus.then("a", "b", "c")` |
| 并行 | `WHEN(a, b)` | `ELBus.when("a", "b")` |
| 并行+任一完成 | `WHEN(a, b).any(true)` | `ELBus.when("a", "b").any(true)` |
| 选择 | `SWITCH(x).TO(a, b)` | `ELBus.switchOpt("x").to("a", "b")` |
| 条件 | `IF(w, a, b)` | `ELBus.ifOpt("w", "a", "b")` |
| 次数循环 | `FOR(n).DO(a)` | `ELBus.forOpt("n").doOpt("a")` |
| 捕获异常 | `CATCH(t).DO(a)` | `ELBus.catchException("t").doOpt("a")` |
| 节点打 tag | `a.tag("t1")` | `ELBus.element("a").tag("t1")` |

> 留白：上表为最简形态；`pre(...)`/`finallyOpt(...)`（前/后置组件，挂在 `then`/`ser` 上）、`elIfOpt(...)`/`elseOpt(...)`（IF 的 else-if/else）、`breakOpt(...)`/`parallel(...)`（循环的 break 与并行）、`must(...)`/`ignoreError(...)`/`customThreadExecutor(...)`（WHEN 的高级控制）、`defaultOpt(...)`（SWITCH 默认分支）等高级子关键字均以同名方法挂在对应 wrapper 上，组合方式与 EL 文本完全一致。唯一例外：EL 关键字 `finally` 是 Java 保留字，对应方法名只能叫 `finallyOpt(...)`，照写 `.finally(...)` 会编译失败。

## 编程式完整示例（注册 Node + 拼 EL + 注册 Chain）

```java
// 1. 动态注册需要的节点（普通组件 + 脚本组件）
LiteFlowNodeBuilder.createCommonNode()
        .setId("a").setName("A").setClazz("com.example.cmp.ACmp").build();
LiteFlowNodeBuilder.createCommonNode()
        .setId("b").setName("B").setClazz("com.example.cmp.BCmp").build();
LiteFlowNodeBuilder.createScriptNode()
        .setId("sc")
        .setName("脚本C")
        .setLanguage("groovy")
        .setScript("println('script node sc')")
        .build();

// 2. 用 ELBus 拼出等价 THEN(a, WHEN(b, sc)) 的表达式
String el = ELBus.then("a", ELBus.when("b", "sc")).toEL();

// 3. 注册为一条 chain（存在则替换，支持热刷新）
LiteFlowChainELBuilder.createChain()
        .setChainId("dynamicChain")
        .setEL(el)
        .build();

// 之后即可正常执行：flowExecutor.execute2Resp("dynamicChain", ...);
```

## 附：EL 表达式静态校验

`LiteFlowChainELBuilder` 提供两个静态方法可在注册前预校验一段 EL 文本（不实际注册 chain）：

- `validate(String elStr)` → `boolean`（已过时，建议用下面的）。
- `validateWithEx(String elStr)` → `ValidationResp`，包含成功/失败及错误信息。

适合在动态拼装/外部输入 EL 后、`build()` 之前先做一次合法性检查。（以源码/官方文档为准的细节可参阅 `ValidationResp` 的字段定义。）
