# 决策路由（Decision Routing）

> 来源文档（相对 `04.v2.16.X文档/`）：
> - `140.🧮决策路由/010.概念以及介绍.md`
> - `140.🧮决策路由/020.决策路由用法.md`
>
> 版本对齐：LiteFlow **v2.16.X**。该特性自 **v2.12.0+** 引入，namespace 维度执行自 **v2.12.1+**。

---

## 一、决策路由解决什么问题

传统执行依赖 `FlowExecutor` 并**必须指定一个 chainId**。但在很多场景里：

- 同时定义了**若干条规则**，事先并不知道该执行哪一条；
- 需要依据**入参动态判断**执行某一条或多条规则；
- 多租户、灰度、A/B、按业务分支分流等链路选择场景。

旧方案是在主规则里用 `SWITCH` 把子规则串起来，本质仍是"执行一条主规则"，且想并行跑多条还要刻意编排，初学者难以上手。

**决策路由**让 LiteFlow 在**不指定 chainId** 的前提下，遍历所有声明了决策条件的 chain，对**决策表达式**求值：符合的 chain 被执行，不符合的跳过。匹配到的多条规则会被**并行执行**。

## 二、核心概念：`<route>` 与 `<body>`

每条 chain 在原有规则体之外，新增两个标签：

- `<route>`：**决策 EL**，决定这条 chain 是否被选中。只能写**与或非表达式**（`AND` / `OR` / `NOT`）或**单个布尔组件**，其中出现的组件**只能是布尔组件**。
- `<body>`：**原来的规则 EL**（`THEN` / `WHEN` / `SWITCH` / `IF` 等正常编排）。

```xml
<chain name="chain1">
    <route>
        AND(r1, r2, r3)
    </route>
    <body>
        THEN(a, b, c);
    </body>
</chain>

<chain name="chain2">
    <route>
        AND(OR(r4, r5), NOT(r3))
    </route>
    <body>
        SWITCH(x).TO(d, e, f);
    </body>
</chain>
```

> `<route>` 中的 `r1..r5` 必须是**布尔组件**（返回 `boolean` 的组件类型），不能是其它任何类型组件。
> 关于布尔组件与与或非表达式的完整定义，参见 `components.md` 与 `el-rules.md`（以官方文档为准）。

## 三、执行方法

`FlowExecutor` 新增了 `executeRouteChain` 系列。最基本的形式：

```java
List<LiteflowResponse> responseList =
        flowExecutor.executeRouteChain(requestData, YourContext.class);
```

特点：

- **不用再传 chainId**——LiteFlow 会遍历所有带 `<route>` 的 chain；
- 决策判断与命中规则的执行均为**并行**；
- 与 `execute2Resp` 一致地支持：用已初始化的上下文传入、多上下文传入等；
- **返回 `List<LiteflowResponse>`**：每个元素对应一条命中规则的执行结果；`LiteflowResponse` 中新增了 **`chainId` 字段**，用于识别是哪条规则产生的结果。

### 错误提示

- 如果规则里**没有任何带 `<route>` 的 chain**，LiteFlow 会报错；
- 如果匹配决策路由后**没有可用规则**，LiteFlow 也会报错提示。

## 四、按 namespace 执行（v2.12.1+）

默认情况下决策路由会执行**所有**带 `<route>` 的 chain。当规则很多、只想判断某一组时，可在 `<chain>` 层加 `namespace` 参数：

```xml
<chain name="chain1" namespace="n1">
    <route>
        AND(r1, r2, r3)
    </route>
    <body>
        THEN(a, b, c);
    </body>
</chain>

<chain name="chain2" namespace="n1">
    <route>
        AND(OR(r4, r5), NOT(r3))
    </route>
    <body>
        SWITCH(x).TO(d, e, f);
    </body>
</chain>

<chain name="chain3" namespace="n2">
    <route>
        r4
    </route>
    <body>
        WHEN(a, b);
    </body>
</chain>
```

调用时传入 namespace（重载方法，**第一个参数为 namespace**）：

```java
// 只在 n1 这个 namespace 内判断 chain1、chain2，选中满足决策条件的执行
List<LiteflowResponse> responseList =
        flowExecutor.executeRouteChain("n1", requestData, YourContext.class);
```

## 五、存储形式的支持范围

决策路由目前支持**文件类规则**与**数据库**两种载体：

- **文件类规则**：XML / JSON / YAML 均可（JSON/YAML 用 `route` key 承载决策 EL，见下节）；
- **数据库**方式（配置见官方"支持决策路由"小节，以官方文档为准）。

**zk / nacos / etcd / apollo / redis 等非文件配置源不支持**决策路由。

## 六、JSON / YAML 格式中的写法

在 JSON / YAML 中也可以写决策体：多了一个 **`route`** key 承载决策 EL；**没有 `body` key**——因为这两种格式里原来的规则体 key 本身就是 **`value`**，照旧保留。（具体 JSON/YAML 示例结构以官方文档为准。）

## 七、关键约束与注意点

1. **组件类型**：`<route>` 里的节点**只能是布尔组件**，不能是其它任何类型的组件。
2. **主表达式**：`<route>` 里的表达式**只能是"与或非表达式"**（`AND` / `OR` / `NOT`），不能用其它主表达式。
3. **上下文隔离**：匹配到的每一条规则都拥有**单独的上下文实例**，运行时**并行执行，互不相干**。
4. **启动检查**：[启动不检查规则]特性对决策路由 EL **不起作用**——决策体中的 EL 在启动时**一定会被检查**；不过决策体中的 EL **可以加 `node` 关键字**。
5. **副表达式**：决策路由体中的 EL **可以加 `tag`、`data` 等副表达式**。
6. **返回识别**：返回是 `List<LiteflowResponse>`，通过其中的 `chainId` 字段区分各命中规则的结果。

---

## 八、与普通 chain 执行的区别（速查）

| 维度 | 普通 chain 执行 | 决策路由 |
|---|---|---|
| 入口方法 | `execute2Resp` / `executeInParam` 等 | `executeRouteChain` |
| 是否指定 chain | **必须**指定 chainId | **不传** chainId，遍历所有带 `<route>` 的 chain |
| 链路选择 | 静态写死，或靠主规则 `SWITCH` 手工编排 | 由决策 EL（布尔组件 + 与或非）动态判定 |
| 命中数量 | 单条 | 0~多条，命中的多条**并行执行** |
| 规则体结构 | 只有规则 EL | `<route>` + `<body>` |
| 上下文 | 单条链路共享 | 每条命中规则**独立上下文实例** |
| 返回类型 | `LiteflowResponse` | `List<LiteflowResponse>`（含 `chainId`） |
| namespace | 不涉及 | 支持 `namespace` 维度筛选（v2.12.1+） |
| 存储支持 | 全部 | 仅 XML 文件 + 数据库 |

---

## 九、最小可运行示例

**规则文件** `route.el.xml`（XML 形式）：

```xml
<chain name="vipChain" namespace="userGroup">
    <route>
        AND(isVip, NOT(inBlacklist))
    </route>
    <body>
        THEN(vipWelcome, vipDiscount);
    </body>
</chain>

<chain name="normalChain" namespace="userGroup">
    <route>
        AND(NOT(isVip), NOT(inBlacklist))
    </route>
    <body>
        THEN(normalWelcome);
    </body>
</chain>
```

**布尔组件示例**（仅示意结构，布尔组件完整写法见 `components.md`）：

```java
@LiteflowComponent("isVip")
public class IsVipCmp extends NodeBooleanComponent {
    @Override
    public boolean processBoolean() {
        // 从上下文 / 请求参数判断是否 VIP
        return Boolean.TRUE.equals(this.getContextBean(UserContext.class).getVip());
    }
}

@LiteflowComponent("inBlacklist")
public class InBlacklistCmp extends NodeBooleanComponent {
    @Override
    public boolean processBoolean() {
        return this.getContextBean(UserContext.class).isBlacklisted();
    }
}
```

**业务组件**（普通组件，写在 `<body>` 中）：

```java
@LiteflowComponent("vipWelcome")
public class VipWelcomeCmp extends NodeComponent {
    @Override
    public void process() {
        System.out.println("welcome vip");
    }
}

@LiteflowComponent("vipDiscount")
public class VipDiscountCmp extends NodeComponent {
    @Override
    public void process() {
        System.out.println("apply vip discount");
    }
}

@LiteflowComponent("normalWelcome")
public class NormalWelcomeCmp extends NodeComponent {
    @Override
    public void process() {
        System.out.println("welcome normal user");
    }
}
```

**配置**（SpringBoot，`application.yml`）：

```yaml
liteflow:
  rule-source: route.el.xml
```

**执行**：

```java
// 仅在 userGroup 这个 namespace 内做决策路由
List<LiteflowResponse> responses =
        flowExecutor.executeRouteChain("userGroup", requestData, UserContext.class);

for (LiteflowResponse resp : responses) {
    System.out.println("命中规则: " + resp.getChainId()
            + "，是否成功: " + resp.isSuccess());
}
```
