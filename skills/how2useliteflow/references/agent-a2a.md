> 对齐 LiteFlow `2.16.2`、AgentScope Java `2.0.3` 和当前 `liteflow-agent-a2a` 客户端实现。

# LiteFlow Agent A2A 客户端

`liteflow-agent-a2a` 把远程 A2A（Agent-to-Agent）Agent 封装成 LiteFlow 节点。它适合“远端本身是一个 Agent”的场景；若远端只暴露若干函数，应使用 MCP 工具；Harness 的远程子代理使用 AgentScope task HTTP，又是另一套协议。

## 1. 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-agent-a2a</artifactId>
    <version>2.16.2</version>
</dependency>
```

A2A 组件不是模型平台组件，不需要实现 `model()`。普通 LiteFlow starter 仍需按应用框架引入。

## 2. 最小组件

下面从远端 well-known 地址解析 Agent Card：

```java
import com.yomahub.liteflow.agent.a2a.A2aAgentComponent;
import com.yomahub.liteflow.agent.context.LiteFlowAgentContext;
import io.agentscope.core.a2a.agent.card.AgentCardResolver;
import io.agentscope.core.a2a.agent.card.WellKnownAgentCardResolver;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import java.util.Map;

@Component("a2aAgent")
public class RemoteAssistantCmp extends A2aAgentComponent {

    private final AgentCardResolver resolver;
    private final String token;

    public RemoteAssistantCmp(
            @Value("${remote.agent.base-url}") String baseUrl,
            @Value("${remote.agent.token}") String token) {
        this.token = token;
        this.resolver = WellKnownAgentCardResolver.builder()
                .baseUrl(baseUrl)
                .authHeaders(Map.of(
                        "Authorization", "Bearer " + token))
                .build();
    }

    @Override
    protected String remoteAgentName() {
        return "remote-assistant";
    }

    @Override
    protected AgentCardResolver agentCardResolver() {
        return resolver;
    }

    @Override
    protected String userPrompt(LiteFlowAgentContext context) {
        Object request = getSlot().getChainReqData(getSlot().getChainId());
        return request == null ? "" : request.toString();
    }
}
```

```properties
liteflow.rule-source=agent/flow.el.xml
liteflow.agent.application-name=my-service

remote.agent.base-url=https://agent.example.com
remote.agent.token=${REMOTE_AGENT_TOKEN}
```

```xml
<chain name="remoteChain">
    THEN(validateInput, a2aAgent, saveResult);
</chain>
```

和 Harness Agent 一样，最终文本默认写入 `Slot.responseData`，错误通过 `LiteflowResponse#getCause()` 取得。

## 3. Agent Card 与鉴权

没有 `liteflow.agent.a2a.*` 配置段，使用 `a2aAgentConfig()` 扩展。

`WellKnownAgentCardResolver.authHeaders(...)` 的请求头**只用于获取 Agent Card**，不会自动应用到后续 JSON-RPC 调用。

远程调用端点也需要鉴权时：

- Agent Card 声明了安全方案：在 `a2aAgentConfig()` 中给 `JSONRPCTransport` 添加 `AuthInterceptor`，按声明提供凭据。
- 想统一追加与 Card security 无关的固定请求头：配置自定义 `ClientCallInterceptor`，无需替换整个 HTTP client。
- 不要误以为 well-known 请求成功就代表后续调用一定携带相同 token。

Agent Card 已声明对应 security scheme 时，可在组件中覆写：

```java
import io.a2a.client.transport.jsonrpc.JSONRPCTransport;
import io.a2a.client.transport.jsonrpc.JSONRPCTransportConfig;
import io.a2a.client.transport.jsonrpc.JSONRPCTransportConfigBuilder;
import io.a2a.client.transport.spi.interceptors.auth.AuthInterceptor;
import io.a2a.client.transport.spi.interceptors.auth.CredentialService;
import io.agentscope.core.a2a.agent.A2aAgentConfig;

@Override
protected A2aAgentConfig a2aAgentConfig() {
    CredentialService credentials = (scheme, context) ->
            "bearerAuth".equals(scheme) ? token : null;
    JSONRPCTransportConfig transport = new JSONRPCTransportConfigBuilder()
            .addInterceptor(new AuthInterceptor(credentials))
            .build();

    return A2aAgentConfig.builder()
            .withTransport(JSONRPCTransport.class, transport)
            .build();
}
```

把 `bearerAuth` 换成远端 Agent Card `securitySchemes` 中的实际 key。`CredentialService` 返回原始 token，`AuthInterceptor` 自动添加 `Bearer `；Card 未声明 `security`／`securitySchemes` 时拦截器不会自行推断鉴权类型。

远端没有 well-known 地址时，业务代码可以构造 `AgentCard`，再由 `FixedAgentCardResolver` 返回。

## 4. 扩展点

`A2aAgentComponent` 必须实现：

| 方法 | 说明 |
|---|---|
| `remoteAgentName()` | 本地用于识别远端 Agent 的稳定名称 |
| `agentCardResolver()` | 动态或固定 Agent Card 解析器 |
| `userPrompt(LiteFlowAgentContext)` | 本次发送给远端的文本 |

可选扩展：

| 方法 | 说明 |
|---|---|
| `a2aAgentConfig()` | 配置 AgentScope `ClientConfig`、Transport、鉴权和 HTTP 行为 |
| `a2aClientRuntimeFactory()` | 替换客户端 Runtime；主要用于自定义 Transport 或离线测试 |
| `resolveConversationId(Slot)` / `agentKey()` | 继承通用会话身份规则 |
| `handleReply(...)` | 改写远端文本的落点 |

LiteFlow 为每个组件惰性创建并复用一个 `A2aClientRuntime`，因此 `agentCardResolver()` 与 `a2aAgentConfig()` 在首次构建 Runtime 时绑定。默认 factory 在每次节点调用时创建独立 `A2aAgent`；AgentScope 又会在每次远端调用的 PreCall 阶段创建 SDK `Client`，并在 PostCall 或 Error 阶段关闭。

LiteFlow 超时或取消会调用一次 `A2aAgent.interrupt()`；远端 `cancelTask` 只是尽力取消，不能保证远端任务和副作用已经停止。自定义 `A2aClientRuntimeFactory` 持有的资源必须由 Runtime 的 `close()` 释放，组件关闭时 LiteFlow 会调用它。`WellKnownAgentCardResolver` 不缓存 Card；稳定 Card 可使用 `FixedAgentCardResolver` 或业务缓存。远端 JSON-RPC 错误会让 LiteFlow chain 失败，不是 Java 工具的 error block 语义。

## 5. 当前能力边界

2.16.2 当前 A2A 客户端：

- 只支持一条用户消息。
- 只支持文本输出，不自动桥接远端流式事件。远端存储、工具和 HITL 由服务端负责。
- 自动携带 `conversationId`、`agentKey`、`traceId` 元数据。
- 受 `liteflow.agent.execution-timeout` 总截止时间约束。
- 使用通用 invocation guard，同一会话身份的并发调用会串行。

结构化输出需求应由远端 Agent 完成后序列化成文本，或在 A2A 节点之后增加普通 LiteFlow 组件解析；不能给当前 A2A 组件直接套 Harness Agent 的 `structuredOutputType()`。

## 6. 客户端与服务端边界

本模块只提供 A2A 客户端，不负责把本地 Agent 暴露成 A2A 服务。服务端需单独依赖 AgentScope `agentscope-extensions-a2a-server:2.0.3` 并自行承载 HTTP。

`AgentScopeA2aServer` 本身不监听端口，也不是 `AutoCloseable`：应用要自行暴露 Agent Card／JSON-RPC Controller，端点真正监听后再调用 `postEndpointReady()`；注入的 `ExecutorService` 也由应用关闭。Card 的 security 声明不会自动完成服务端认证授权，应在网关、Filter 或 Controller 实现。默认 runner 每请求创建 Agent 但不负责关闭，生产环境应自定义 runner，在 complete／error／cancel 后释放 Agent。仓库里的 `MinimalA2aServer` 只是测试夹具。

三种远端集成不要混淆：

| 需求 | 机制 |
|---|---|
| 把远端函数暴露给本地 Agent 调用 | MCP，见 `agent-models-tools.md` |
| 把远端 Agent 当 LiteFlow 节点 | `A2aAgentComponent` |
| Harness 主 Agent 派生远程子任务 | `SubagentDeclaration.url(...)`，见 `agent-harness.md` |

## 7. 测试

- 组件与 Runtime 契约：`liteflow-testcase-el-agent` 中的 `A2aAgentComponentTest`、`A2aClientRuntimeTest`。
- Spring 链集成：`liteflow-testcase-el-agent/feature/a2a`。
- 真实/最小服务连通：`liteflow-testcase-el-agent/real/a2a`，包含 `MinimalA2aServer` 和 live test。
- 离线测试可覆写 `a2aClientRuntimeFactory()` 返回记录请求的 fake runtime，断言 prompt、metadata、超时和响应转换。

## 8. 常见报错

| 报错 / 症状 | 原因 | 处理 |
|---|---|---|
| `A2A client requires exactly one UserMessage` | 输入不是单条用户文本 | 先在本地合并消息，再发一条文本 |
| `A2A client supports TEXT output only` | 请求结构化或其他输出 | 让远端返回文本，后续节点解析 |
| Agent Card 能读取，调用却 401 | authHeaders 只用于 Card | 给 JSON-RPC Transport 配 `AuthInterceptor` 或自定义 HTTP client |
| well-known 不存在 | 远端不发布 Card 地址 | 使用 `FixedAgentCardResolver` |
| 调用超时 | 远端耗时超过总截止时间 | 检查 `execution-timeout`、网络和远端处理时间 |
| 多次请求意外串行 | 应用名、conversationId、agentKey 相同 | 这是状态保护；只有真正独立的会话才使用不同 conversationId |
