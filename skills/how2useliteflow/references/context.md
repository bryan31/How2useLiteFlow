> 来源：官方文档 `04.v2.16.X文档/080.🌮上下文/` 目录（010.说明、020.数据上下文的定义和使用、030.用初始化好的上下文传入、040.给上下文设置别名、050.上下文参数注入、060.用表达式获取上下文参数）。版本对齐 LiteFlow **v2.16.X**。

# 数据上下文（Context）

## 上下文是什么

- 执行器执行流程时，会为**每个请求**分配独立的数据上下文实例，不同请求间完全隔离。
- 组件之间**不直接传参**，所有业务数据都放进上下文：每个组件只从上下文取自己关心的数据、把自己产生的结果写回上下文，从而在数据层面解耦、达到可编排的目的。
- 一旦把数据放进上下文，整个链路中的任一节点都能取到。

## 定义与使用

### 默认上下文

LiteFlow 提供 `DefaultContext`，内部主要存储容器就是一个 Map，通过 `setData` / `getData` 存取。

> 官方建议自定义上下文。`DefaultContext` 是弱类型，存取需要强转，实际业务中不便。

### 自定义 POJO 上下文

LiteFlow 对上下文 Bean 没有任何要求，任意 Bean 都能当上下文。自定义上下文本质就是一个值对象，强类型更贴合业务。

定义后缀示例（纯 POJO，框架无要求）：

```java
public class OrderContext {
    private String orderNo;
    // getter / setter 省略
}
```

执行时传入上下文 class：

```java
// 第 2 个参数为流程初始参数；第 3 个参数起为上下文 class
LiteflowResponse response = flowExecutor.execute2Resp("chain1", 流程初始参数, OrderContext.class);
```

LiteFlow 会在调用时初始化、分配唯一实例。组件内取上下文：

```java
@LiteflowComponent("yourCmpId")
public class YourCmp extends NodeComponent {

    @Override
    public void process() {
        OrderContext context = this.getContextBean(OrderContext.class);
        // 只有一个上下文时，下面这种取法等价
        // OrderContext context = this.getFirstContextBean();
    }
}
```

### 多上下文（v2.8.0+）

执行时可同时声明多个上下文 class，框架会分别初始化：

```java
LiteflowResponse response = flowExecutor.execute2Resp(
        "chain1", 流程初始参数,
        OrderContext.class, UserContext.class, SignContext.class);
```

组件内按 class 获取：

```java
@LiteflowComponent("yourCmpId")
public class YourCmp extends NodeComponent {

    @Override
    public void process() {
        OrderContext orderContext = this.getContextBean(OrderContext.class);
        UserContext   userContext  = this.getContextBean(UserContext.class);
        SignContext   signContext  = this.getContextBean(SignContext.class);

        // getFirstContextBean() 取第一个（即 OrderContext）
    }
}
```

### 用超类获取上下文（v2.12.2+）

通用组件场景下，可用上下文的**超类**来获取，避免绑定具体类型：

```java
public class OrderContext extends BaseContext {
    ...
}
```

```java
// 调用时仍传具体子类
flowExecutor.execute2Resp("chain1", 流程初始参数, OrderContext.class);
```

```java
@LiteflowComponent("yourCmpId")
public class YourCmp extends NodeComponent {
    @Override
    public void process() {
        BaseContext context = this.getContextBean(BaseContext.class);
    }
}
```

> 注意：若链路中有多个上下文都是同一超类的子类，用超类获取只会拿到**第一个**。

## 传入已初始化的上下文实例（v2.8.4+）

正常情况下上下文初始化由框架完成，执行第一个组件时上下文内没有用户数据；流程入参通过 `this.getRequestData()` 获取，**不包含在上下文里**。把入参放进上下文需要你自己做。

如果觉得繁琐，可以直接传入**已初始化好的 bean 实例**（支持多上下文）：

```java
OrderContext orderContext = new OrderContext();
orderContext.setOrderNo("SO11223344");
LiteflowResponse response = flowExecutor.execute2Resp("chain1", null, orderContext);
```

这样上下文里已有数据，某种意义上等同于流程入参，因此可以不再传流程入参。

> **禁止混传**：框架不支持 bean 与 class 混传，要么都传 bean，要么都传 class。

## 上下文别名

### `@ContextBean` 别名（v2.12.0+）

在上下文类上标注别名：

```java
@ContextBean("anyName")
public class YourContext {
    ...
}
```

执行时写法不变：

```java
// 传 class
LiteflowResponse response = flowExecutor.execute2Resp("chain1", 流程初始参数, YourContext.class);
// 或传已初始化的 bean
YourContext context = new YourContext();
context.setXxxx(yyy);
LiteflowResponse response = flowExecutor.execute2Resp("chain1", 流程初始参数, context);
```

组件内按别名获取：

```java
@Component("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        TestContext context = this.getContextBean("anyName");
    }
}
```

> 别名在多上下文且**两个上下文是同一个类**时特别有用——按 class 取可能取错，按别名可以规避。

### 默认名称

未声明 `@ContextBean` 时，也可按名称取到，名称为 **className 首字母小写**。例如类名 `PriceContext`，则 `this.getContextBean("priceContext");` 可以取到。

## 上下文参数注入（v2.12.1+，仅声明式组件）

> 仅适用于**声明式组件**（方法级别式 / 类级别式均可），普通继承式组件不支持。

声明式组件中通常会先取上下文再取属性。从 v2.12.1 起可用 `@LiteflowFact` 在方法参数上**直接注入**上下文属性，省去取 context 的样板代码。

假设上下文：

```java
public class TestContext {
    private User user;
    private String data1;
    // getter setter 省略
}
```

基本注入：

```java
@LiteflowComponent
public class CmpConfig {

    @LiteflowMethod(value = LiteFlowMethodEnum.PROCESS, nodeType = NodeTypeEnum.COMMON, nodeId = "a")
    public void processA(NodeComponent bindCmp,
                         @LiteflowFact("user") User user) {
        user.setName("jack");
    }
}
```

点操作符取深层属性（`User.company.address`）：

```java
@LiteflowMethod(value = LiteFlowMethodEnum.PROCESS, nodeType = NodeTypeEnum.COMMON, nodeId = "a")
public void processA(NodeComponent bindCmp,
                     @LiteflowFact("user.company.address") String address) {
    // do biz
}
```

注入多个参数：

```java
@LiteflowMethod(value = LiteFlowMethodEnum.PROCESS, nodeType = NodeTypeEnum.COMMON, nodeId = "a")
public void processA(NodeComponent bindCmp,
                     @LiteflowFact("user.name") String name,
                     @LiteflowFact("data1") String data1) {
    // do biz
}
```

**多上下文匹配规则**：LiteFlow 会按类型在所有上下文中**智能搜索匹配**，无需指定上下文。

> 注意：如果多个上下文里都有同名属性（如两个上下文都有 `user`），注入拿到的是**第一个**，在不同环境下可能不同，会产生错乱。请确保被注入的对象在多个上下文中只有一份；否则可用点操作符**显式指定上下文前缀**：

```java
@LiteflowFact("orderContext.id") Integer orderId
@LiteflowFact("memberContext.id") Integer memberId
```

## 用 EL 表达式取/设上下文参数（v2.13.1+，通用）

> 这是真正意义上的**通用**特性，无论**继承式组件、声明式组件，还是脚本组件**都可使用。

### 取值：`getContextValue`

传统写法强绑上下文类型：

```java
YourContext context = this.getContextBean(YourContext.class);
String userCode = context.getUserCode();
```

用表达式取参，组件与上下文彻底解耦：

```java
@Component("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        String userCode = this.getContextValue("userCode");
    }
}
```

点操作符取深层属性：

```java
// 取上下文中 member 对象的 code 字段
String code = this.getContextValue("member.code");
```

**多上下文匹配规则**：表达式会自动匹配最合适的上下文。但若多个上下文有相同字段（如 `OrderContext`、`MemberContext`、`AuthContext` 都有 `code`），`getContextValue("code")` 只返回**第一个匹配**。需要精确指定时，加**上下文前缀**：

```java
String code = this.getContextValue("authContext.code");
```

前缀默认是上下文类名首字母小写；如果用了 `@ContextBean`，则改用别名作前缀：

```java
@ContextBean("authCxt")
public class AuthContext {
    private String code;
    ...
}
// 此时用 authCxt 而非 authContext
String code = this.getContextValue("authCxt.code");
```

对 List / Map / 数组的内置支持：

```java
String a = this.getContextValue("userList.get(0)");     // List
String b = this.getContextValue("dataMap.get('key')");  // Map
String c = this.getContextValue("nameArray[0]");        // 数组
```

### 设值：`setContextValue`

方法签名（支持多参数方法）：

```java
public void setContextValue(String methodExpress, Object... values) { ... }
```

调用上下文的 setter（表达式里写**方法名**）：

```java
String name = this.getContextValue("name");
this.setContextValue("setDesc", "hello," + name);  // 调用上下文的 setDesc(...)
```

点操作符给更深层对象赋值：

```java
this.setContextValue("member.setDesc", "xxxx");
```

指定上下文前缀调用方法：

```java
this.setContextValue("memberContext.member.setDesc", "xxxx");
```

> 多上下文时 `getContextValue` / `setContextValue` 均无需关心数据来自哪个上下文，框架自动匹配；只有同名歧义时才需加前缀。

---

## 速查表

| 场景 | API / 注解 | 版本 |
|---|---|---|
| 取上下文实例（按 class） | `this.getContextBean(Class)` | — |
| 取首个上下文实例 | `this.getFirstContextBean()` | — |
| 按超类取 | `this.getContextBean(BaseContext.class)` | v2.12.2+ |
| 按别名/默认名取 | `this.getContextBean("anyName")` | v2.12.0+ |
| 上下文别名 | `@ContextBean("anyName")`（标在上下文类上） | v2.12.0+ |
| 声明式组件参数注入 | `@LiteflowFact("字段路径")` | v2.12.1+（仅声明式） |
| 表达式取值 | `this.getContextValue("member.code")` | v2.13.1+（通用） |
| 表达式设值 | `this.setContextValue("setDesc", value)` | v2.13.1+（通用） |
| 多上下文执行 | `execute2Resp(chain, 入参, C1.class, C2.class, ...)` | v2.8.0+ |
| 传入已初始化 bean | `execute2Resp(chain, null, ctxBean)`（不可与 class 混传） | v2.8.4+ |
