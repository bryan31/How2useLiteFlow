# 快速开始（Hello World）

> 来源文档（相对 `04.v2.16.X文档/`）：
> - `040.🍟快速开始(Hello world)/005.说明.md`
> - `040.🍟快速开始(Hello world)/010.Springboot场景安装运行.md`
> - `040.🍟快速开始(Hello world)/020.Spring场景安装运行.md`
> - `040.🍟快速开始(Hello world)/030.Solon场景安装运行.md`
> - `040.🍟快速开始(Hello world)/040.其他场景安装运行.md`
>
> 版本对齐：LiteFlow **v2.16.X**（示例中以 `2.16.1` 为准）。

本章帮助你在最短时间内跑通 LiteFlow。根据项目实际环境，从 SpringBoot / Spring / Solon / 非 Spring 四种场景中选择一种。建议跟着文档操作一遍。下面以 **SpringBoot 场景为主线**给出完整最小可运行示例，其余场景只列关键差异点。

---

## 一、SpringBoot 场景（主线，完整最小示例）

### 1. 引入依赖

LiteFlow 提供 `liteflow-spring-boot-starter`，带自动装配。

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot-starter</artifactId>
    <version>2.16.1</version>
</dependency>
```

:::tip SpringBoot 4.X 用户
`liteflow-spring-boot-starter` 适用于 SpringBoot **2.X ~ 3.X**。
若使用 **SpringBoot 4.X**（要求 JDK17 及以上），改用 `liteflow-spring-boot4-starter`，其余用法完全一致：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot4-starter</artifactId>
    <version>2.16.1</version>
</dependency>
```
:::

### 2. 定义组件

继承 `NodeComponent`，实现 `process()`，用 `@LiteflowComponent("id")` 标注，确保被 SpringBoot 扫描注册。

```java
@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() {
        //do your business
    }
}
```

同理定义 b、c 组件：

```java
@LiteflowComponent("b")
public class BCmp extends NodeComponent {
    @Override
    public void process() { /* ... */ }
}

@LiteflowComponent("c")
public class CCmp extends NodeComponent {
    @Override
    public void process() { /* ... */ }
}
```

### 3. 配置文件

在 `application.properties`（或 `application.yml`）中指定规则文件路径。更多配置项见官方「配置项」章节。

```properties
liteflow.rule-source=config/flow.xml
```

:::tip v2.16.1 起：Rule-DB 模式（规则存数据库，推荐生产使用）
上例 `rule-source` 是本地规则文件方式。v2.16.1 起也可改用 **Rule-DB 统一规则数据库**模式——规则/脚本以数据库为权威源，支持多实例热更新与统一发布 API，更适合生产环境：

- 依赖：`liteflow-rule-db-sql` / `-postgresql` / `-mongodb` / `-redis` / `-zk` / `-etcd` / `-nacos` 七选一；
- 配置：改用 `liteflow.rule-db.*`，此时**不再配置 `rule-source`**（两者互斥、同配启动报错）。

完整接入步骤与各后端配置见 `references/rule-db.md`。
:::

### 4. 规则文件

在 `resources/config/flow.xml` 中定义链路。SpringBoot 启动时会自动装载规则文件。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<flow>
    <chain name="chain1">
        THEN(a, b, c);
    </chain>
</flow>
```

### 5. 启动类

用 `@ComponentScan` 把组件包扫入 Spring 上下文。

```java
@SpringBootApplication
@ComponentScan({"com.xxx.xxx.cmp"})  // 把你定义的组件扫入 Spring 上下文
public class LiteflowExampleApplication {
    public static void main(String[] args) {
        SpringApplication.run(LiteflowExampleApplication.class, args);
    }
}
```

### 6. 注入 FlowExecutor 执行

在任意被 Spring 托管的类中注入 `FlowExecutor`，调用 `execute2Resp` 执行链路并拿到 `LiteflowResponse`。

```java
@Component
public class YourClass {

    @Resource
    private FlowExecutor flowExecutor;

    public void testConfig() {
        LiteflowResponse response = flowExecutor.execute2Resp("chain1", "arg", DefaultContext.class);
    }
}
```

> `DefaultContext` 是默认上下文；也可传入自己的任意 Bean 当作上下文（传 Bean 的 `Class` 属性）。详见官方「数据上下文」章节。

---

## 二、Spring 场景（关键差异点）

适用于**用了 Spring 但没用 SpringBoot** 的项目。

- **依赖坐标**：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring</artifactId>
    <version>2.16.1</version>
</dependency>
```

- **组件定义**：与 SpringBoot 完全一致，仍用 `@LiteflowComponent("a")`。
- **配置方式**：不使用 `application.properties`，而是在 **Spring XML** 里手动声明 Bean：

```xml
<context:component-scan base-package="com.yomahub.flowtest.components" />

<bean id="springAware" class="com.yomahub.liteflow.spi.spring.SpringAware"/>

<bean class="com.yomahub.liteflow.spring.ComponentScanner"/>

<bean id="liteflowConfig" class="com.yomahub.liteflow.property.LiteflowConfig">
    <property name="ruleSource" value="config/flow.xml"/>
</bean>

<bean id="flowExecutor" class="com.yomahub.liteflow.core.FlowExecutor" depends-on="springAware">
    <property name="liteflowConfig" ref="liteflowConfig"/>
</bean>

<!-- 如果 enableLog 为 false，下面这段也可以省略 -->
<bean class="com.yomahub.liteflow.monitor.MonitorBus">
    <constructor-arg ref="liteflowConfig" />
</bean>
```

- **规则文件**：与 SpringBoot 一致，`resources/config/flow.xml`，Spring 启动时自动装载。
- **执行**：与 SpringBoot 完全一致，注入 `FlowExecutor` 后调用 `flowExecutor.execute2Resp("chain1", "arg", DefaultContext.class)`。

---

## 三、Solon 场景（关键差异点）

适用于使用 [Solon](https://solon.noear.org/) 框架的项目。

- **依赖坐标**：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-solon-plugin</artifactId>
    <version>2.16.1</version>
</dependency>
```

- **组件定义差异**：继承式组件既可用 Solon 的 `@Component("id")`，也可用 LiteFlow 的 `@LiteflowComponent("id")`；当前源码与测试均支持。优先用 `@LiteflowComponent` 可与 Spring 写法保持一致。

```java
import com.yomahub.liteflow.annotation.LiteflowComponent;

@LiteflowComponent("a")
public class ACmp extends NodeComponent {
    @Override
    public void process() { /* ... */ }
}
```

- **配置文件**：与 SpringBoot 一致，`liteflow.rule-source=config/flow.xml`（properties/yml 均可）。更多配置项见官方「Solon 下的配置项」章节。
- **规则文件**：`resources/config/flow.xml`，Solon 启动时自动装载，写法与 SpringBoot 一致。
- **启动类**：用 `@SolonMain`，通过 `@Import` 指定配置。

```java
@SolonMain
@Import(profiles="classpath:/application.properties")
public class LiteflowExampleApplication {
    public static void main(String[] args) {
        Solon.start(App.class, args);
    }
}
```

- **执行**：用 Solon 的 `@Inject` 注入 `FlowExecutor`：

```java
@Component
public class YourClass {

    @Inject
    private FlowExecutor flowExecutor;

    public void testConfig() {
        LiteflowResponse response = flowExecutor.execute2Resp("chain1", "arg", DefaultContext.class);
    }
}
```

---

## 四、其他场景（非 Spring 体系）

适用于未使用 Spring/SpringBoot 的项目。LiteFlow 文档中 **98% 以上**的特性在非 Spring 体系下都能生效，但有如下限制：

- `ruleSource` 的**模糊路径匹配**特性不生效。
- `@LiteflowComponent` **无法使用**（组件需在规则文件里显式声明类）。
- **监控功能**不可用。

### 1. 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-core</artifactId>
    <version>2.16.1</version>
</dependency>
```

### 2. 定义组件

普通类继承 `NodeComponent` 即可，**无需任何注解**。

```java
public class ACmp extends NodeComponent {
    @Override
    public void process() { /* ... */ }
}
```

### 3. 规则文件中显式注册节点

非 Spring 体系下，组件需要在 `flow.xml` 的 `<nodes>` 节点里通过全限定类名注册：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<flow>
    <nodes>
        <node id="a" class="com.yomahub.liteflow.test.component.AComponent"/>
        <node id="b" class="com.yomahub.liteflow.test.component.BComponent"/>
        <node id="c" class="com.yomahub.liteflow.test.component.CComponent"/>
    </nodes>

    <chain name="chain1">
        THEN(a, b, c);
    </chain>
</flow>
```

### 4. 手动初始化 FlowExecutor

通过 `FlowExecutorHolder.loadInstance(config)` 初始化：

```java
LiteflowConfig config = new LiteflowConfig();
config.setRuleSource("config/flow.xml");
FlowExecutor flowExecutor = FlowExecutorHolder.loadInstance(config);
```

> **注意**：`FlowExecutor` 初始化相对较重，**全局只需初始化一次**。建议在项目启动时或第一次执行时初始化，不要每次执行都重新初始化。

### 5. 执行

```java
LiteflowResponse response = flowExecutor.execute2Resp("chain1", "arg", DefaultContext.class);
```

---

## 各场景速查对照表

| 维度 | SpringBoot | Spring | Solon | 非 Spring |
|---|---|---|---|---|
| **artifactId** | `liteflow-spring-boot-starter`（4.X 用 `liteflow-spring-boot4-starter`） | `liteflow-spring` | `liteflow-solon-plugin` | `liteflow-core` |
| **groupId / version** | `com.yomahub` / `2.16.1` | 同左 | 同左 | 同左 |
| **组件注解** | `@LiteflowComponent("id")` | `@LiteflowComponent("id")` | `@LiteflowComponent("id")` 或 Solon 的 `@Component("id")` | 无注解，规则文件 `<node class="...">` 注册 |
| **配置方式** | `application.properties` 配 `liteflow.rule-source` | Spring XML 声明 `LiteflowConfig` / `FlowExecutor` 等 Bean | 同 SpringBoot（properties/yml） | 代码构造 `LiteflowConfig` + `FlowExecutorHolder.loadInstance` |
| **获取 FlowExecutor** | `@Resource` 注入 | `@Resource` 注入 | `@Inject` 注入 | `FlowExecutorHolder.loadInstance(config)` |
| **执行 API** | `flowExecutor.execute2Resp(chainId, arg, DefaultContext.class)` | 同左 | 同左 | 同左 |
| **规则文件路径** | `resources/config/flow.xml` | 同左 | 同左 | 同左（无模糊路径匹配） |

> 说明：执行 API 三参签名 `execute2Resp(chainId, initialRequest, contextClass)` 中，`DefaultContext` 为默认上下文，可换成任意自定义 Bean 的 `Class`。本文件未覆盖的细节（如完整配置项清单、自定义上下文用法、EL 语法）以官方对应章节为准。
