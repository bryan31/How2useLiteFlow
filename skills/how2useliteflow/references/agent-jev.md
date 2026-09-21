# Jev 智能选择组件（2.16.2）

依据本次 `2.16.2` 工作区新增的 `liteflow-agent-jev`、`JevConfig`、`JevProvider` 与离线测试核验，日期为 2026-09-21。模块版本沿用 `2.16.2`，不代表已发布到 Maven 仓库；依赖无法解析时使用包含本次更新的源码构建，不能仅凭版本号假定已有该模块。

## 1. 定位与依赖

`com.yomahub.liteflow.agent.jev.JevSwitchComponent` 继承 `NodeSwitchComponent`，按 `provider` 通过 TypeSafe 的 System One 接口或 OpenRouter 的 Decisions API 发起一次 Jev Choice 请求，将目标 ID 交给 `SWITCH(...).to(...).DEFAULT(...)` 执行。适合从若干已定义的处理分支中按文本或业务数据选择一条。

要求 **JDK 17+**。模块直接依赖 `liteflow-core`，不依赖 `liteflow-agent-core` 或 AgentScope，不需要聊天模型、会话存储、工作区或 Harness 初始化。它也不使用 `executeRouteChain` 遍历 `<route>`：该能力要求布尔组件，详见 [decision-routing.md](decision-routing.md)。

在已有 LiteFlow 应用中添加：

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-agent-jev</artifactId>
    <version>2.16.2</version>
</dependency>
```

Spring Boot 应用仍需 `liteflow-spring-boot-starter`；Boot 4 使用 `liteflow-spring-boot4-starter`。完整框架接入见 [quickstart.md](quickstart.md)。

## 2. 配置

TypeSafe 入口（默认）：

```yaml
liteflow:
  rule-source: config/flow.el.xml
  agent:
    jev:
      provider: typesafe
      api-key: ${JEV_API_KEY}
      timeout: 3s
      min-confidence: 0.6
```

`JEV_API_KEY` 使用 TypeSafe 的凭据。通过 OpenRouter 调用时，将 `jev` 配置替换为：

```yaml
liteflow:
  agent:
    jev:
      provider: openrouter
      api-key: ${OPENROUTER_API_KEY}
      timeout: 3s
      min-confidence: 0.6
```

`OPENROUTER_API_KEY` 使用 OpenRouter 的凭据。两种入口的依赖与组件写法相同，不需要额外引入 `liteflow-agent-openai`。

| `provider` | 默认 `base-url` | 自动追加的接口路径 | 默认 `model` |
| --- | --- | --- | --- |
| `typesafe`（默认） | `https://api.typesafe.ai/v1` | `/systemone` | `jev-1.13.0` |
| `openrouter` | `https://openrouter.ai/api/alpha` | `/decisions` | `typesafe/jev-1.13` |

`base-url`、`model` 未设置、为 `null` 或为空白时，使用所选 provider 的默认值。显式覆盖值会保留，不受 setter 调用顺序影响；切换 provider 时应移除旧值或一并更新，不能只改 provider 后仍保留 TypeSafe 的地址与模型。

`base-url` 填 API 根地址，支持网关路径和末尾斜杠；不要包含客户端会追加的 `/systemone` 或 `/decisions`。OpenRouter 使用 Decisions API，不能填写聊天接口的 `/api/v1` 地址，也不配置到 `openai-compatible` 中。

`timeout` 限制完整 HTTP 响应的等待时间，包括响应体；它独立于 Harness 的 `liteflow.agent.execution-timeout`。`min-confidence` 可在组件中覆写 `minConfidence()`，有效范围为闭区间 `[0, 1]`，并要求有限数值。

Spring Boot 在属性绑定时拒绝未知 `provider`；API Key、地址、超时与阈值等运行约束在执行 Jev 组件时校验，普通组件和其他 Agent 不需要 Jev 凭据。Java 配置使用 `JevConfig#setProvider(JevProvider.OPENROUTER)`，枚举位于 `com.yomahub.liteflow.property.agent` 包，不接受字符串 setter。通过 `LiteflowConfig.getAgent().getJev()` 设置，或调用 `AgentConfig.setJev(JevConfig)`。六项配置的完整约束见 [agent-config.md](agent-config.md#8-jev-智能选择)。

## 3. 组件与 EL

下面接收字符串流程入参，将原始决策保存到本次流程的上下文。两个 public 类分别放在各自的 Java 文件中，按项目补充 package。

```java
import com.yomahub.liteflow.agent.jev.JevChoiceResult;
import com.yomahub.liteflow.agent.jev.JevSwitchComponent;
import com.yomahub.liteflow.annotation.LiteflowComponent;
import java.util.Map;

@LiteflowComponent("supportRouter")
public class SupportRouter extends JevSwitchComponent {
    @Override
    protected Object state() {
        return getRequestData();
    }

    @Override
    protected String instructions() {
        return "根据客户当前诉求选择处理分支，注意否定和意图变化。";
    }

    @Override
    protected Map<String, String> choices() {
        return Map.of("refund", "客户希望退款", "exchange", "客户希望换货");
    }

    @Override
    protected void onDecision(JevChoiceResult result) {
        getContextBean(SupportContext.class).setDecision(result);
    }
}
```

```java
import com.yomahub.liteflow.agent.jev.JevChoiceResult;

public class SupportContext {
    private JevChoiceResult decision;

    public JevChoiceResult getDecision() {
        return decision;
    }

    public void setDecision(JevChoiceResult decision) {
        this.decision = decision;
    }
}
```

假定已注册三个业务组件 `refund`、`exchange`、`manual`，规则文件 `config/flow.el.xml` 为：

```xml
<flow>
    <chain name="supportChain">
        SWITCH(supportRouter).to(refund, exchange).DEFAULT(manual);
    </chain>
</flow>
```

调用已有 `flowExecutor`：

```java
LiteflowResponse response = flowExecutor.execute2Resp(
        "supportChain", "我不想换货了，请帮我退款", SupportContext.class);
if (!response.isSuccess()) {
    throw new IllegalStateException("Jev routing failed", response.getCause());
}
JevChoiceResult decision = response.getContextBean(SupportContext.class).getDecision();
```

`processSwitch()` 已由框架实现且为 `final`，业务实现 `state()`、`instructions()`、`choices()` 即可。

- `state()` 支持字符串、可序列化为 JSON 对象的业务数据或数组；不接受 null、数字或布尔值。只传选择所需的数据。
- `instructions()` 与每个候选描述必须非空白。
- `choices()` 返回 1～254 个目标 ID 到业务描述的映射。ID 可指向组件或子链，必须在**当前** `.to(...)` 目标列表中恰好出现一次；不必列出 `.to(...)` 的全部目标。
- ID 不得为空白、包含冒号或等于 `JevSwitchComponent.NO_MATCH`。当前不支持 `tag:...` 选择语法，也不接受同 ID 的多个目标。
- 框架自动加入保留项 `__liteflow_no_match__`，代表均不适用或信息不足；不要手动加入候选，也不要把它作为业务目标。

## 4. 结果、默认分支与异常

| 情况 | 执行结果 |
| --- | --- |
| 有效目标且 `confidence >= minConfidence()` | 执行选中的一个目标，等于阈值也命中 |
| 有效目标但置信度低于阈值 | 返回空字符串，由 `SWITCH` 执行 `DEFAULT` |
| 选择 `NO_MATCH` | 无论置信度多高，都走 `DEFAULT` |
| 需要默认分支但没有配置 `DEFAULT` | 沿用 `NoSwitchTargetNodeException` |
| HTTP 非 200、网络失败、超时、非法响应 | 抛出 `JevInvocationException`，不会自动走 `DEFAULT` |
| 配置、输入或候选约束不合法 | 请求前抛出 `IllegalArgumentException` |
| 等待时被中断 | 取消请求等待，保留线程中断标记，抛出 `InterruptedException` |

`JevInvocationException.getStatusCode()` 返回 HTTP 错误状态码；没有 HTTP 错误响应时为 `0`。客户端不自动重试，也不跟随重定向。响应中的选项、置信度和概率分布须合法；不能把响应解析错误解释成业务上的“均不适用”。技术失败如需统一处理，可以明确使用 LiteFlow 的 `CATCH(...).DO(errorHandler)`，其中处理器由应用注册。

`onDecision(JevChoiceResult)` 在当前流程线程中、目标执行前调用。正常命中、低置信度、`NO_MATCH` 的有效答案都会调用；请求或协议失败不会调用。回调抛出异常会阻止目标执行。

`JevChoiceResult` 是 Java record，读取方法为 `model()`、`choice()`、`confidence()`、`probabilities()`，没有 `getChoice()` 等 Bean getter。`model()` 保留服务端返回的实际模型标识，可能与请求中的模型别名不同；两种 provider 都保留响应中的置信度和概率，不由客户端重新估算。概率 Map 不可变；记录的是阈值判断前的原始结果，因此走 `DEFAULT` 时 `choice()` 仍可能是 `refund`。置信度需要结合业务样本校准，不能等同于单次判断正确率。

组件实例会被并发复用；决策和请求状态应放在本次执行的 Context 中，不要保存到组件成员字段。并行分支若共用一个 Context 字段，还需自行处理覆盖或并发写入。

## 5. 离线验证与源码入口

在包含本次更新的 LiteFlow 源码仓库中运行：

```bash
mvn -pl liteflow-testcase-el/liteflow-testcase-el-agent-jev -am test -DskipTests=false
```

`JevChoiceClientTest` 通过本地 HTTP 服务验证两种 provider 的默认值、覆盖值、请求路径、响应保留、异常、超时和中断；`JevSwitchComponentTest` 验证真实分支执行、子链、阈值边界、默认分支、回调和并发复用。Spring Boot 2/3 与 Boot 4 的 `AgentPropertyBindingTest` 验证 `jev.*` 属性绑定，包括 provider 默认值、OpenRouter 配置及未知 provider 拒绝。不需要真实 API Key；这些测试不衡量真实模型的中文识别效果。

以下路径均相对 LiteFlow 仓库：

- 模块说明：`liteflow-agent/liteflow-agent-jev/README.md`。
- 组件、HTTP 客户端、结果和异常：`liteflow-agent/liteflow-agent-jev/src/main/java/com/yomahub/liteflow/agent/jev/`。
- 配置、provider 与默认值：`liteflow-core/src/main/java/com/yomahub/liteflow/property/agent/` 下的 `JevConfig.java`、`JevProvider.java`。
- 离线测试：`liteflow-testcase-el/liteflow-testcase-el-agent-jev/src/test/java/com/yomahub/liteflow/agent/jev/`。
