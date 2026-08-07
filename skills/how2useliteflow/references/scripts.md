> 来源：LiteFlow 官方文档 `04.v2.16.X文档/100.🍋脚本组件/`（脚本语言介绍、各脚本引擎、脚本与 Java 交互、多语言混合、文件脚本、动态刷新、验证、卸载）。版本对齐 v2.16.1（源码基线 2.16.1.1），依赖坐标示例版本为 `2.16.1`；`liteflow-script-javax-pro` 例外——≤2.16.1 存在 ThreadLocal 泄漏（bug #IK6XVN，2.16.1.1 修复），其坐标示例为 `2.16.1.1`（见第三、四节）。

# 脚本组件（Script Component）

## 一、概念与定位

脚本组件允许用**脚本**而非 Java 类来定义组件，脚本可被**即时调整/热刷新**。LiteFlow 在启动时对脚本进行预编译，性能接近原生 Java（但不及原生），换取的是无需重启即可改逻辑的灵活性。

- 适用：需要经常变动的小部分逻辑。
- 不适用：固定不变的逻辑（仍推荐 Java 类）。
- 官方推荐组合：`Java 类组件 + 脚本组件 + EL 表达式`，不要把所有逻辑都写成脚本。

## 二、四种脚本节点类型（`type`）

所有脚本语言共用以下 4 种 `type`：

| type | 名称 | 脚本返回要求 |
|---|---|---|
| `script` | 普通脚本节点 | 无需返回 |
| `switch_script` | 选择脚本节点 | 返回选择的节点 Id |
| `boolean_script` | 条件（布尔）脚本节点 | 返回 `true`/`false` |
| `for_script` | 数量循环节点 | 返回数值，表示循环次数 |

:::warning
脚本组件**无法定义循环迭代组件**（iterator）。需要循环请用 `for_script`；Java 脚本中即使继承了 `NodeIteratorComponent` 也无法正确执行。
:::

## 三、支持的语言与依赖坐标

LiteFlow 支持 **8 种**脚本语言，对应下表 **11 个**插件坐标（Java 有 3 个插件、JS 有 2 个引擎）。`groupId` 统一为 `com.yomahub`，版本随主版本（示例为 `2.16.1`；`liteflow-script-javax-pro` 因下述泄漏修复，示例为 `2.16.1.1`）。

| 语言 | Maven artifactId | 备注 / 版本要求 |
|---|---|---|
| Groovy | `liteflow-script-groovy` | 语法接近 Java，可在脚本内定义类 |
| Java（推荐） | `liteflow-script-javax-pro` | v2.13.0+；基于 Liquor，**须用 JDK 不能用 JRE**；v2.15.3+ 仅推荐此插件；**≤2.16.1 有 ThreadLocal 泄漏（#IK6XVN），务必用 2.16.1.1+** |
| Java（旧） | `liteflow-script-java` | 基于 Janino，v2.11.0+，**已不推荐维护** |
| Java（旧） | `liteflow-script-javax` | 基于 Liquor，v2.12.4+，**已不推荐维护** |
| JavaScript | `liteflow-script-javascript` | 基于 JDK 自带引擎，仅 ES5；仅 JDK8 可用 |
| JavaScript (ES6) | `liteflow-script-graaljs` | 基于 GraalJs，支持 ES6；JDK11/17 只能用此引擎 |
| QLExpress | `liteflow-script-qlexpress` | — |
| Python | `liteflow-script-python` | 依赖 **Jython** 环境，需额外安装配置 |
| Lua | `liteflow-script-lua` | 调用 Java 方法用 `:` 而非 `.` |
| Aviator | `liteflow-script-aviator` | 调用 Java 方法为 `method(bean, args)` 形式 |
| Kotlin | `liteflow-script-kotlin` | v2.12.1+；上下文必须通过 `bindings` 获取 |

> 说明：Groovy/JS/QLExpress/Python/Lua/Aviator/Kotlin 文档均明确列出支持上述 4 种 `type`。Java（javax-pro）为类式定义，节点 `type` 仍按上表使用（如迭代场景改用 `for_script`），具体行为以源码/官方文档为准。

:::warning
**javax-pro ≤2.16.1 存在 ThreadLocal 泄漏（bug #IK6XVN，2.16.1.1 已修复）**：`liteflow-script-javax-pro` 的编译产物是跨执行共享的单例，≤2.16.1 中每次执行脚本组件时（`process`/`isAccess`/`onSuccess` 等所有执行入口）都会向 `NodeComponent` 的 `ThreadLocal<Stack<Node>> refNodeStackTL` 压入 refNode 却不清理，线程池线程上的栈随调用次数无界增长，长期运行有内存膨胀甚至 OOM 风险。2.16.1.1 起所有执行入口统一在 `finally` 中 `removeRefNode()` 清理。**使用 javax-pro（官方首推的 Java 脚本插件）请升级到 2.16.1.1 及以上**。另见 `faq-pitfalls.md` 中该问题的条目。
:::

## 四、规则文件中定义脚本节点

通过 `<node>` 的 `type` 与 `language` 属性定义，脚本内容放在 `<![CDATA[ ]]>` 中。

**普通脚本（Groovy 示例）：**

```xml
<node id="s1" name="普通脚本1" type="script" language="groovy">
    <![CDATA[
    import cn.hutool.core.date.DateUtil

    def date = DateUtil.parse("2022-10-17 13:31:43")
    defaultContext.setData("demoDate", date)

    def a = 3
    def b = 2
    defaultContext.setData("s1", a * b)
    ]]>
</node>
```

**选择脚本（QLExpress，返回节点 Id）：**

```xml
<node id="s2" name="条件脚本" type="switch_script">
    <![CDATA[
        count = defaultContext.getData("count");
        if(count > 100){
            return "a";
        }else{
            return "b";
        }
    ]]>
</node>
```

**Python 示例（注意中文需 decode）：**

```xml
<node id="s1" name="普通脚本1" type="script" language="python">
    <![CDATA[
        a=6
        b=10
        if a>5:
            b=5
        defaultContext.setData("s1",a*b)
    ]]>
</node>
```

**Lua 示例（Java 方法用 `:` 调用）：**

```xml
<node id="s1" name="普通脚本1" type="script" language="lua">
    <![CDATA[
        local a=6
        local b=10
        defaultContext:setData("s1",a*b)
        defaultContext:setData("s2",_meta:get("nodeId"))
    ]]>
</node>
```

**Aviator 示例（`method(bean, args)` 调用形式）：**

```xml
<node id="s1" name="普通脚本1" type="script" language="aviator">
    <![CDATA[
        use java.util.Date;
        use cn.hutool.core.date.DateUtil;
        let d = DateUtil.formatDateTime(new Date());
        println(d);

        a = 2;
        b = 3;
        setData(defaultContext, "s1", a*b);
    ]]>
</node>
```

**JavaScript 示例：**

```xml
<node id="s1" name="普通脚本1" type="script" language="js">
    <![CDATA[
        var a=3; var b=2;
        function addByArray(values){
            var sum=0;
            for(var i=0;i<values.length;i++){ sum+=values[i]; }
            return sum;
        }
        defaultContext.setData("s1", parseInt(addByArray([a,b])));
    ]]>
</node>
```

**Kotlin 示例（上下文必须经 `bindings` 取）：**

```xml
<node id="s1" type="script" language="kotlin">
    import com.yomahub.liteflow.slot.DefaultContext

    fun sum(a: Int, b: Int) = a + b
    var a = 2
    var b = 3
    val defaultContext = bindings["defaultContext"] as DefaultContext
    defaultContext.setData("s1", sum(a, b))
</node>
```

**Java（javax-pro）示例 —— 类式定义，与静态 Java 完全一致：**

Maven 依赖（≤2.16.1 有 ThreadLocal 泄漏（#IK6XVN），请使用 `2.16.1.1` 及以上）：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-script-javax-pro</artifactId>
    <version>2.16.1.1</version>
</dependency>
```

```xml
<node id="s1" name="普通脚本1" type="script" language="java">
    <![CDATA[
    import com.yomahub.liteflow.core.NodeComponent;
    import com.yomahub.liteflow.slot.DefaultContext;
    import com.yomahub.liteflow.spi.holder.ContextAwareHolder;

    public class Demo extends NodeComponent {
        @Override
        public void process() throws Exception {
            int v1 = 2; int v2 = 3;
            DefaultContext ctx = this.getFirstContextBean();
            ctx.setData("s1", v1 * v2);
        }
    }
    ]]>
</node>
```

> javax-pro 中可用 `this`，可覆盖 `isAccess`、`beforeProcess` 等方法。无法用 `@Resource`/`@Autowired` 注入 Spring Bean，需用 `ContextAwareHolder.loadContextAware().getBean(XxxClass.class)`。

## 五、脚本内可用绑定变量

### 5.1 适用 6 种语言（groovy/js/python/qlexpress/lua/aviator）

通过**上下文类名 simpleClassName 的驼峰形式**直接引用上下文。例如上下文类 `OrderContext` → 脚本中 `orderContext`；`UserContext` → `userContext`；默认上下文 `DefaultContext` → `defaultContext`。

```groovy
def name = userContext.userName         // 字段
def name = userContext.getUserName()    // getter
userContext.doYourMethod();             // 调用任意方法
```

- 自定义引用名：在上下文类上加 `@ContextBean("userCtx")`，脚本中即可用 `userCtx` 引用（v2.10.0+）。

### 5.2 元数据 `_meta`

| 关键字 | 含义 |
|---|---|
| `_meta.slotIndex` | slot 下标，可用 `FlowBus.getSlot(slotIndex)` 取 slot |
| `_meta.currChainId` | 当前执行的 chain 名 |
| `_meta.nodeId` | 当前 node Id |
| `_meta.tag` | tag 值 |
| `_meta.cmpData` | 组件规则参数（data 语法） |
| `_meta.loopIndex` | 循环中的下标 |
| `_meta.loopObject` | 迭代循环中的循环对象 |
| `_meta.requestData` | 流程初始参数 |
| `_meta.subRequestData` | 当前隐式流程入参（仅隐式流程内可取） |

- `_meta.cmp`：相当于 `this`（当前组件对象）。例：`_meta.cmp.getTag()`、`_meta.cmp.getContextBean("xxx")`。

### 5.3 各语言差异要点

- **Lua**：调用 Java 方法用 `:`，如 `defaultContext:setData("k", v)`。
- **Aviator**：调用 Java 方法为 `method(bean, args)` 反射式，如 `setName(userContext, "jack")`；可用 `use java.util.Date;` 导入 Java 类。
- **Kotlin**：上下文及一切元信息必须通过 `bindings` 关键字获取，如 `bindings["defaultContext"]`。
- **Java（javax-pro）**：类式，用 `this.getFirstContextBean()` 取上下文，`ContextAwareHolder.loadContextAware().getBean(...)` 取 Spring Bean。

## 六、脚本与 Java 交互

### 6.1 注入自定义 JavaBean：`@ScriptBean`

在 Spring 体系中，给 Java 对象加 `@ScriptBean("demo")` 即可在脚本中用 `demo` 关键字调用其方法。

```java
@Component
@ScriptBean("demo")
public class DemoBean1 {
    @Resource
    private DemoBean2 demoBean2;

    public String getDemoStr1(){ return "hello"; }
    public String getDemoStr2(String name){ return demoBean2.getDemoStr2(name); }
}
```

- 指定可访问方法：`@ScriptBean(name="demo", includeMethodName={"test1","test2"})`
- 排除方法：`@ScriptBean(name="demo", excludeMethodName={"test2","test3"})`
- 前提：对象必须注册进 Spring 上下文，否则注解无效。

### 6.2 直接注入方法：`@ScriptMethod`（v2.9.5+）

适合只暴露个别方法的场景：

```java
@Component
public class DemoBean1 {
    @ScriptMethod("demo")
    public String getDemoStr1() { return "hello"; }
}
```

脚本中：`demo.getDemoStr1()`。同样要求 bean 注册进 Spring 上下文。

### 6.3 非 Spring 环境

手动注册：

```java
ScriptBeanManager.addScriptBean("demo", new DemoBean());
```

## 七、多脚本语言混合共存（v2.10.0+）

可在同一规则文件内用不同语言书写不同脚本节点，前提是引入了对应语言的依赖。各脚本节点间参数通过上下文互通。

```xml
<nodes>
    <node id="s1" name="groovy脚本" type="script" language="groovy">
        <![CDATA[ defaultContext.setData("s1", 3*2) ]]>
    </node>
    <node id="s2" name="js脚本" type="script" language="js">
        <![CDATA[ defaultContext.setData("k", 1); ]]>
    </node>
    <node id="s3" name="python脚本" type="script" language="python">
        <![CDATA[ defaultContext.setData("s3", 3*3) ]]>
    </node>
</nodes>
<chain name="chain1">
    THEN(a, s1, b, s2, c, s3);
</chain>
```

## 八、文件脚本（外部脚本文件）

把脚本写到独立文件（IDE 有语法高亮/提示），用 `file` 属性指定路径：

- 相对路径（v2.6.4+）：`<node id="s1" type="script" file="xml-script-file/s1.groovy"/>`
- 绝对路径（v2.9.7+）：`<node id="s1" type="script" file="/data/liteflow/s1.groovy"/>`

```xml
<nodes>
    <node id="s1" name="普通脚本" type="script"  file="xml-script-file/s1.groovy"/>
    <node id="s2" name="选择脚本" type="switch_script" file="xml-script-file/s2.groovy"/>
</nodes>
```

## 九、动态刷新 / 热更新脚本（v2.12.0+）

无需重启即可更新某个节点的脚本内容：

```java
LiteflowMetaOperator.reloadScript(nodeId, script);
```

（整规则的热刷新也包含脚本热刷新。）

## 十、验证脚本

- v2.12.0+，返回布尔：

```java
boolean isValid = ScriptValidator.validate(script);
```

- v2.15.0+，带回错误信息：

```java
ValidationResp resp = ScriptValidator.validateWithEx(script);
boolean isSuccess = resp.isSuccess();
Exception e = resp.getCause();
```

> 上面这两个**单参重载仅在 classpath 只引入一种脚本插件时可用**。当同时加载了多个脚本插件（即第七节的多语言混合共存场景）时，单参版无法推断目标语言，会直接校验失败，错误信息为 `The loaded script modules more than 1. Please specify the script language.`（源码 `ScriptValidator.java:55-58`），此时必须改用下面 10.1 的「指定语言」重载。

### 10.1 多脚本插件共存：指定 `ScriptTypeEnum`

当引入了多个脚本插件时，必须显式传入 `ScriptTypeEnum` 指定按哪种语言校验（源码 `ScriptValidator.java:91-104`）：

```java
// 返回布尔
boolean isValid = ScriptValidator.validate(script, ScriptTypeEnum.GROOVY);

// 带回错误信息
ValidationResp resp = ScriptValidator.validateWithEx(script, ScriptTypeEnum.GROOVY);
```

一次校验多种语言的脚本，用批量重载 `validate(Map<ScriptTypeEnum, String>)`，Map 的 key 即该段脚本的语言（源码 `ScriptValidator.java:112-119`）：

```java
Map<ScriptTypeEnum, String> scripts = new HashMap<>();
scripts.put(ScriptTypeEnum.GROOVY, groovyScript);
scripts.put(ScriptTypeEnum.JS, jsScript);
scripts.put(ScriptTypeEnum.PYTHON, pythonScript);
boolean allValid = ScriptValidator.validate(scripts);
```

`ScriptTypeEnum` 枚举取值（源码 `ScriptTypeEnum.java`，共 8 个可用值）：

| 枚举值 | displayName | 归并说明 |
|---|---|---|
| `GROOVY` | groovy | — |
| `JS` | js | **JDK 原生 `liteflow-script-javascript` 与 ES6 的 `liteflow-script-graaljs` 两个引擎都归 `JS`** |
| `PYTHON` | python | — |
| `QLEXPRESS` | qlexpress | — |
| `LUA` | lua | — |
| `AVIATOR` | aviator | — |
| `JAVA` | java | **`liteflow-script-java`/`javax`/`javax-pro` 三个 Java 插件都归 `JAVA`** |
| `KOTLIN` | kotlin | — |

## 十一、卸载脚本（v2.12.0+）

```java
FlowBus.unloadScriptNode(String nodeId);
```

该方法会卸载已编译的 script，并在元数据中删除对应节点。
