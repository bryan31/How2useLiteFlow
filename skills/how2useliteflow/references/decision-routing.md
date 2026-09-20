# 决策路由（Decision Routing）

> 来源文档（相对 `04.v2.16.X文档/`）：
> - `140.🧮决策路由/010.概念以及介绍.md`
> - `140.🧮决策路由/020.决策路由用法.md`
> - `115.🏦Rule-DB模式/050.快速开始(Redis).md`（Rule-DB 发布 route/namespace 示例）
> - `115.🏦Rule-DB模式/130.内存与性能.md`（Rule-DB 路由冷加载预警）
>
> 版本对齐：LiteFlow **v2.16.X**。该特性自 **v2.12.0+** 引入，namespace 维度执行自 **v2.12.1+**，Rule-DB 模式（**v2.16.1** 新增）同样支持决策路由。

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

- **不用再传 chainId**——LiteFlow 会遍历所有带 `<route>` 的 chain（准确说是目标 namespace 内的，不传 namespace 时即默认 namespace，见下节）；
- 决策判断与命中规则的执行均为**并行**；
- 与 `execute2Resp` 一致地支持传上下文 Class 或现成 Bean，也支持多个上下文；但路由执行会并发复用 Bean，具体边界见下文；
- **返回 `List<LiteflowResponse>`**：每个元素对应一条命中规则的执行结果；`LiteflowResponse` 中新增了 **`chainId` 字段**，用于识别是哪条规则产生的结果。

### 错误提示

- 当前 namespace 下**没有任何带 `<route>` 的 chain** 时，抛 **`com.yomahub.liteflow.exception.RouteChainNotFoundException`**，消息形如 `no route found for namespace[default]`；
- 决策表达式求值后**没有任何命中规则**时，抛 **`com.yomahub.liteflow.exception.NoMatchedRouteChainException`**，消息为 `there is no matched route chain`。

想对"无命中"做降级（而不是让异常冒出）时，可单独 catch `NoMatchedRouteChainException` 区分处理。

## 四、按 namespace 执行（v2.12.1+）

不传 namespace 时，决策路由只判断**默认 namespace（`default`）**下带 `<route>` 的 chain——即所有**未声明 `namespace` 属性**的 chain（解析时会被赋予默认 namespace `default`）。当规则很多、只想判断某一组时，可在 `<chain>` 层加 `namespace` 参数：

> **注意**：一旦给部分 chain 声明了 namespace，这些 chain 就**不再参与**不传 namespace 的默认调用，必须用对应 namespace 的重载；若默认 namespace 下已没有任何带 `<route>` 的 chain，默认调用会直接抛 `RouteChainNotFoundException`（`no route found for namespace[default]`）。

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

决策路由支持的载体：

- **文件类规则**：XML / JSON / YAML 均可（JSON/YAML 用 `route` key 承载决策 EL，见下节）；
- **数据库**方式（配置见官方"支持决策路由"小节，以官方文档为准）；
- **Rule-DB 模式**（v2.16.1 新增）：route 作为 chain 元数据随规则一同存储与发布（发布 API 的 `.route(...)` / `.namespace(...)`），SQL / PostgreSQL / MongoDB / Redis / ZooKeeper / Etcd / Nacos 各 Rule-DB 后端均支持决策路由，详见 `rule-db.md`。

**zk / nacos / etcd / apollo / redis 等传统 rule-source 配置源插件不支持**决策路由——"不支持"仅指这些老式插件；上述 v2.16.1 Rule-DB 模式即使使用 redis / zk / etcd / nacos 后端也不在此列。

> **性能预警（Rule-DB 模式）**：Rule-DB 模式下首次 `executeRouteChain` 为拿到 route 元数据，会在路由执行前把**所有还没就绪的 Rule-DB chain 逐个回源并编译**，而不是只加载最终匹配的那一条。规则清单大又用路由模式时，请把第一次路由请求当成一次**批量冷加载**：压测其延迟，并考虑用 `rule-db.cache.preload-chain-ids` 启动预热抹平，或拆分 application-name（详见 `rule-db.md`）。

## 六、JSON / YAML 格式中的写法

在 JSON / YAML 中也可以写决策体：多了一个 **`route`** key 承载决策 EL；**没有 `body` key**——因为这两种格式里原来的规则体 key 本身就是 **`value`**，照旧保留。

最小 JSON 示例：

```json
{
  "flow": {
    "chain": [
      {
        "name": "chain1",
        "route": "AND(r1, r2)",
        "value": "THEN(a, b);"
      }
    ]
  }
}
```

YAML 同理：chain 条目下并列 `route` 与 `value` 两个 key（另有可选 `namespace` key），无 `body` key。注意：定义了 `route` 就必须同时保留 `value`，否则解析时抛 `FlowSystemException`。

## 七、关键约束与注意点

1. **组件类型**：`<route>` 里的节点**只能是布尔组件**，不能是其它任何类型的组件。
2. **主表达式**：`<route>` 里的表达式**只能是"与或非表达式"**（`AND` / `OR` / `NOT`），不能用其它主表达式。
3. **上下文实例并非一概隔离**：传 Class 时，每次 route 判断和每次命中 body 执行都会重新创建上下文，因此 route 中写入的数据不会带到 body；传 Bean 时，同一批对象会被所有 route/body 并发复用。需要跨 route/body 共享数据时应明确使用线程安全的 Bean，或把判定所需数据放在只读 `param` 中。
4. **启动检查**：[启动不检查规则]特性对决策路由 EL **不起作用**——决策体中的 EL 在启动时**一定会被检查**；不过决策体中的 EL **可以加 `node` 关键字**。
5. **副表达式**：决策路由体中的 EL **可以加 `tag`、`data` 等副表达式**。
6. **返回识别**：返回是 `List<LiteflowResponse>`，通过其中的 `chainId` 字段区分各命中规则的结果。

---

## 八、与普通 chain 执行的区别（速查）

| 维度 | 普通 chain 执行 | 决策路由 |
|---|---|---|
| 入口方法 | `execute2Resp` / `execute2Future` | `executeRouteChain` |
| 是否指定 chain | **必须**指定 chainId | **不传** chainId，遍历所有带 `<route>` 的 chain |
| 链路选择 | 静态写死，或靠主规则 `SWITCH` 手工编排 | 由决策 EL（布尔组件 + 与或非）动态判定 |
| 命中数量 | 单条 | 0~多条，命中的多条**并行执行** |
| 规则体结构 | 只有规则 EL | `<route>` + `<body>` |
| 上下文 | 单条链路共享 | Class：route/body 各自新实例；Bean：所有 route/body 并发复用同一批对象 |
| 返回类型 | `LiteflowResponse` | `List<LiteflowResponse>`（含 `chainId`） |
| namespace | 不涉及 | 支持 `namespace` 维度筛选（v2.12.1+） |
| 存储支持 | 全部 | 文件类（XML / JSON / YAML）+ 数据库（含 v2.16.1 Rule-DB） |

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
