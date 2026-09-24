# 测试用例与示例

> 来源：官方文档 `04.v2.16.X文档/170.⛱测试用例以及示例/010.测试用例.md`、`020.DEMO案例.md`，以及 LiteFlow 源码 `liteflow-testcase-el/` 下 30+ 测试模块（已用源码核对真实写法）。
> 对齐版本：LiteFlow **2.16.2**。项目内有 **2000+ 测试用例**，覆盖了绝大多数公开功能——**遇到“某个功能到底怎么用”，去对应测试模块找例子是最可靠的途径**。

---

## 一、为什么要看测试模块

文档讲"是什么"，测试模块讲"实际怎么写"。LiteFlow 的测试用例按**框架环境 × 功能特性 × 配置源 × 脚本语言**组织，几乎每个功能点都有可运行的样例。把它们当作"权威示例库"：

- 想确认某写法是否正确 → 找对应模块里的测试类照搬。
- 用 AI 辅助时，可以让 AI（按 SKILL.md 决策流程）去 `liteflow-testcase-el/` 检索真实样例再回答，避免臆测。

---

## 二、SpringBoot 下的标准测试范式（最高频）

取自源码 `liteflow-testcase-el-springboot/.../test/multiContext/MultiContextELSpringbootTest.java`（@since 2.6.4，JUnit 5）：

```java
package com.yomahub.liteflow.test.multiContext;

import com.yomahub.liteflow.core.FlowExecutor;
import com.yomahub.liteflow.flow.LiteflowResponse;
import com.yomahub.liteflow.test.BaseTest;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.test.context.TestPropertySource;

import javax.annotation.Resource;

@TestPropertySource(value = "classpath:/multiContext/application.properties")
@SpringBootTest(classes = MultiContextELSpringbootTest.class)
@EnableAutoConfiguration
@ComponentScan({ "com.yomahub.liteflow.test.multiContext.cmp" })
public class MultiContextELSpringbootTest extends BaseTest {

    @Resource
    private FlowExecutor flowExecutor;

    @Test
    public void testMultiContext1() throws Exception {
        LiteflowResponse response = flowExecutor.execute2Resp(
                "chain1", "arg", OrderContext.class, CheckContext.class);
        OrderContext orderContext = response.getContextBean(OrderContext.class);
        CheckContext checkContext = response.getContextBean(CheckContext.class);

        Assertions.assertTrue(response.isSuccess());
        Assertions.assertEquals("SO12345", orderContext.getOrderNo());
        Assertions.assertEquals("987XYZ", checkContext.getSign());
    }
}
```

要点：
- **JUnit 5**：`org.junit.jupiter.api.Test` / `Assertions`。
- **三个注解组合**：`@SpringBootTest(classes = 当前测试类.class)` + `@EnableAutoConfiguration` + `@ComponentScan({"...组件包"})`；用 `classes` 指向自身以最小化上下文。
- **`@TestPropertySource(value = "classpath:/<功能>/application.properties")`**：每个测试类指向**自己专属**的测试资源目录下的 `application.properties`（里面配 `liteflow.rule-source=<功能>/flow.el.xml` 等），互不干扰。
- **`extends BaseTest`**：见下一节的全局状态清理（**强烈建议继承**，否则多测试类间会互相污染）。
- **断言**：`response.isSuccess()` 判成功；`response.getContextBean(XxxContext.class)` 取上下文再断字段；异常用 `Assertions.assertThrows(...)`。

### 规则文件放在哪
测试规则文件放在 `src/test/resources/<功能>/` 下、与 `application.properties` 同目录，由 `@TestPropertySource` 的路径统一指定。EL 规则文件的真实命名约定是 `flow.el.xml`（或 `flow.el.json`/`flow.el.yml`；经典格式为 `flow.xml`/`flow.json`/`flow.yml`）——**没有纯 `flow.el` 这种文件**。例（源码 `multiContext/application.properties` 原文）：

```properties
# src/test/resources/multiContext/application.properties
liteflow.rule-source=multiContext/flow.el.xml
```

> **后缀白名单**：本地 rule-source 路径只认 `.xml`/`.json`/`.yml`/`.el.xml`/`.el.json`/`.el.yml` 六种后缀（`liteflow-core` 的 `FlowParserProvider.ConfigRegexConstant` 正则，`FlowParserProvider.java:136-148`）；写成 `flow.el` 这类不识别后缀会在启动解析时抛 `ErrorSupportPathException`（"can't support the format ..."）。

---

## 三、关键坑：测试类间的全局状态清理（`BaseTest`）

LiteFlow 大量使用**全局静态状态**（`FlowBus` 的 chain/node 注册表、组件扫描缓存、slot 池、SPI、生命周期、切面等）。多个测试类同跑时，上一组的注册会"漏"到下一组，导致莫名其妙的失败。

源码 `liteflow-testcase-el-springboot/.../test/BaseTest.java` 用 `@AfterAll` 统一清理：

```java
public class BaseTest {
    @AfterAll
    public static void cleanScanCache() {
        FlowBus.cleanMonitorFile();
        ComponentScanner.cleanCache();
        FlowBus.cleanCache();
        ExecutorHelper.loadInstance().clearExecutorServiceMap();
        SpiFactoryInitializing.clean();
        LiteflowConfigGetter.clean();
        FlowInitHook.cleanHook();
        FlowBus.clearStat();
        SpringCmpAroundAspectHolder.clean();
        LifeCycleHolder.clean();
    }
}
```

→ **写测试时让你的测试类 `extends BaseTest`**（或复制这套清理逻辑），可避免绝大多数"单跑过、合跑挂"的问题。

---

## 四、非 Spring（nospring）场景

`liteflow-testcase-el-nospring` 提供**纯 Java**用法：规则用 `<nodes>` 注册组件类，并用 `FlowExecutorHolder.loadInstance(config)` 做**全局一次**初始化（见 `references/quickstart.md` 的"其他场景"）。测试同样继承各自 BaseTest 做清理。

---

## 五、Spring 原生（springnative）与 Solon 的测试范式

非 SpringBoot 环境**不要**套用 `@SpringBootTest` 范式，源码里的真实写法如下。

**Spring 原生**（`liteflow-testcase-el-springnative`，例 `PreAndFinallyELSpringTest.java:21-26`）：JUnit 5 的 Spring 扩展 + XML 上下文：

```java
@ExtendWith(SpringExtension.class)
@ContextConfiguration("classpath:/preAndFinally/application.xml")
public class PreAndFinallyELSpringTest extends BaseTest {
    @Resource
    private FlowExecutor flowExecutor;
}
```

组件扫描、`LiteflowConfig`（`ruleSource` 指向 `preAndFinally/flow.el.xml`）、`FlowExecutor` 都以 bean 形式写在该 `application.xml` 里。

**Solon**（`liteflow-testcase-el-solon`，例 `PreAndFinallyELSpringbootTest.java:20-25`）：

```java
@SolonTest
@Import(profiles="classpath:/preAndFinally/application.properties")
public class PreAndFinallyELSpringbootTest extends BaseTest {
    @Inject
    private FlowExecutor flowExecutor;
}
```

liteflow 配置写在 `@Import` 引入的 properties 里（同样是 `liteflow.rule-source=preAndFinally/flow.el.xml`），用 `@Inject` 注入 `FlowExecutor`。两种范式都同样 `extends` 各自模块的 `BaseTest` 做全局清理。

---

## 六、功能/场景 → 测试模块速查（找示例用）

> 用 `scripts/source-lookup.sh find <关键字>` 或 `grep` 在 `liteflow-testcase-el/` 下定位真实样例。

| 想看什么 | 看哪个模块 |
|---|---|
| SpringBoot 通用功能（组件/EL/上下文/循环/选择…） | `liteflow-testcase-el-springboot` |
| SpringBoot 4（JDK17+） | `liteflow-testcase-el-springboot4` |
| Spring 原生（非 Boot） | `liteflow-testcase-el-springnative` |
| Solon | `liteflow-testcase-el-solon`（Solon 下 SQL 配置源示例见 `liteflow-testcase-el-sql-solon`） |
| 非 Spring | `liteflow-testcase-el-nospring` |
| 类级声明式组件 | `liteflow-testcase-el-declare-springboot` |
| 方法级声明式组件 | `liteflow-testcase-el-declare-multi-springboot` |
| Groovy/JS(graaljs)/Python/Lua/Aviator/Java/Kotlin/QLExpress 脚本 | `liteflow-testcase-el-script-*-springboot` |
| 多脚本语言共存 | `liteflow-testcase-el-script-multi-language-springboot` |
| 动态构造 EL（ELBus 等） | `liteflow-testcase-el-builder` |
| 决策路由 | `liteflow-testcase-el-routechain` |
| ZK/SQL/Nacos/Apollo/Etcd/Redis 配置源 | `liteflow-testcase-el-(zk|sql|nacos|apollo|etcd|redis)-springboot` |
| SQL 多数据源 / sharding-jdbc / 动态 | `liteflow-testcase-el-sql-springboot-{dynamic,sharding-jdbc}` 等 |
| Agent 底层运行时、工具调用、HITL（JDK17+） | `liteflow-testcase-el-agent-core` |
| Jev 协议、智能选择、是非判断、laya provider 与默认分支（JDK17+，本地 HTTP 模拟） | `liteflow-testcase-el-agent-jev`，用法见 [agent-jev.md](agent-jev.md) |
| Agent Harness、压缩、长期记忆、沙箱（JDK17+） | `liteflow-testcase-el-agent-harness` |
| LiteFlow Agent 组件与端到端编排（JDK17+） | `liteflow-testcase-el-agent` |
| Metrics 指标采集 / 装配守护 / 端点（v2.16.1+） | `liteflow-testcase-el-springboot` 的 `test/metrics/`（`MetricsScenarioSpringbootTest`、`MetricsLifeCycleGuardTest`、`MetricsEndpointSpringbootTest`；资源 `resources/metrics/`、`metrics-scenario/`）；Boot4 端点见 `liteflow-testcase-el-springboot4` 的 `test/metrics/MetricsEndpointSpringboot4Test` |
| 节点执行生命周期钩子 `PostProcessNodeExecuteLifeCycle`（v2.16.1+） | `liteflow-testcase-el-springboot` 的 `test/nodeexecute/`（`NodeExecuteLifeCycleSpringbootTest` + `TestNodeExecuteLifeCycle`，资源 `resources/nodeexecute/`） |
| Rule-DB 核心／发布 API／七后端 | `liteflow-testcase-el-rule-db-core`、`-publisher`、`-sql-springboot`、`-postgresql-springboot`、`-mongodb-springboot`、`-redis-springboot`、`-etcd-springboot`、`-zk-springboot`、`-nacos-springboot`；七后端均有 Boot 4 对应模块 |
| Rule-DB 配置绑定（v2.16.1+） | `liteflow-testcase-el-springboot`、`liteflow-testcase-el-springboot4` 与 `liteflow-testcase-el-solon` 的 `test/config/RuleDbConfigBindingTest` |

四个 Agent 测试模块由 Maven profile `testcase-agent` 纳入聚合构建；该 profile 在 JDK 17+ 自动激活，也可显式指定。例如：

```bash
mvn test -Ptestcase-agent -pl liteflow-testcase-el/liteflow-testcase-el-agent-core
mvn test -Ptestcase-agent -pl liteflow-testcase-el/liteflow-testcase-el-agent-jev -am -DskipTests=false
mvn test -Ptestcase-agent -pl liteflow-testcase-el/liteflow-testcase-el-agent-harness
mvn test -Ptestcase-agent -pl liteflow-testcase-el/liteflow-testcase-el-agent
```

> 2.16.2 仓库根目录另有 `scripts/verify-rule-db-{publisher,sql,postgresql,mongodb,redis,etcd,zk}-release.sh` 发布验证脚本（非 JUnit）；Nacos 以对应 Spring Boot 2/3 与 Boot 4 测试模块覆盖。

---

## 七、外部 DEMO 案例（官方提供）

- 短信系统选供应商：`https://github.com/bryan31/message-demo`
- 电商价格计算引擎（带界面）：`https://gitee.com/bryan31/liteflow-example`
- 外置规则存储（DB/ZK/Nacos/Etcd）：`https://github.com/bryan31/liteflow-ext-rule-demo`

> 这些是外部仓库链接，仅作指引；如需细节请用户自行查阅或按 fallback 协议处理，不要凭链接内容臆测其内部实现。

---

## 八、给 AI 的提示

- 当用户问"某功能怎么写/怎么测"时，**优先**指向对应的测试模块（上表）作为权威示例；必要时用 `source-lookup.sh` 在 `liteflow-testcase-el/` 检索真实代码再回答。
- 生成测试代码时，**务必带上 `extends BaseTest`（或等价清理）** 与每个类独立的 `@TestPropertySource`，否则容易踩全局状态污染的坑。
- 断言用 JUnit 5 的 `Assertions`；取上下文用 `response.getContextBean(...)`，详见 `references/executor.md`。

## 九、2.16.2 Agent guide 对应验证

离线测试使用 ScriptedChatModel／假工具，不需要模型 Key：

| 能力 | 测试类 |
|---|---|
| guide 最小聊天组件 | AgentGuideQuickStartTest |
| 默认值与配置绑定 | AgentGuideDefaultsTest、AgentPropertyBindingTest |
| 会话身份与展示历史 | InvocationIdentityResolverTest、AgentConversationServiceTest、HarnessConversationServiceTest |
| 同会话工作区协调 | CrossAgentWorkspaceGuardTest |
| 自动压缩与动态技能 | AdaptiveCompactionMiddlewareTest、SessionSkillWorkspaceTest |
| ExecuteOption 与链路入口 | AgentChainGuideTest |

仓库脚本 `liteflow-testcase-el/scripts/run-agent-guide-tests.sh unit` 跑完整离线组；integration 需要 Docker 与预置数据库／沙箱镜像，live 需要真实平台凭据。只核验文档改动时优先 Maven `-Dtest=类名列表 -Dsurefire.failIfNoSpecifiedTests=false -am` 选择对应模块。不要把离线通过当作数据库／平台连通性验证。
