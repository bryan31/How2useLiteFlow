> 对齐 LiteFlow `2.16.2` 与 AgentScope Java `2.0.3`。依据 `docs/liteflow-agent-guide.md`、`HarnessAgentComponent` 和 `AbstractAgentScopeComponent`；核验日期为 2026-09-19。

# LiteFlow Agent：快速开始与编排

本文负责 Agent 的接入、执行、多 Agent 编排、运行时生命周期、可靠性和测试。按问题继续读取：

- 模型、Java/内置/MCP 工具、中间件、Skills：`agent-models-tools.md`。
- 会话、StateStore、事件、结构化输出、HITL、并发和配置：`agent-state-events-hitl.md`。
- 上下文压缩、长期记忆、沙箱、计划和子代理：`agent-harness.md`。
- 调用远程 A2A Agent：`agent-a2a.md`。
- 从 2.16.1 旧 Agent API 迁移：`react-agent.md`。

## 1. 定位与模块

`liteflow-agent` 把一个大模型 Agent 封装成普通 LiteFlow 组件。Agent 因而可以和 Java 组件、脚本组件一起参与 `THEN`、`WHEN`、`IF`、`SWITCH` 等所有 EL 编排。

**运行要求**：JDK 17+。LiteFlow 核心仍支持 JDK 8～25，但 Agent 模块不能在 JDK 8～16 中使用。

Maven groupId 均为 `com.yomahub`：

| 模块 | 作用 |
|---|---|
| `liteflow-agent-core` | `HarnessAgentComponent`、模型抽象、工具、会话、历史、事件、HITL、压缩、记忆、计划、子代理、沙箱 |
| `liteflow-agent-openai` | OpenAI、DeepSeek、Kimi、GLM、MiniMax、OpenAI 兼容端点 |
| `liteflow-agent-anthropic` | Anthropic 和兼容网关 |
| `liteflow-agent-gemini` | Google Gemini |
| `liteflow-agent-dashscope` | DashScope / 通义千问 |
| `liteflow-agent-redis` | Redis StateStore |
| `liteflow-agent-mysql` | MySQL StateStore |
| `liteflow-agent-a2a` | A2A 协议客户端 |

业务项目引入 starter、core 和模型平台模块；平台模块也会传递 core。当前聚合模块共有 8 个子模块，独立 harness 模块已合并到 core。

## 2. 五步跑通

### 2.1 依赖

```xml
<properties>
    <liteflow.version>2.16.2</liteflow.version>
</properties>

<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot-starter</artifactId>
    <version>${liteflow.version}</version>
</dependency>

<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-agent-core</artifactId>
    <version>${liteflow.version}</version>
</dependency>

<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-agent-openai</artifactId>
    <version>${liteflow.version}</version>
</dependency>
```

Spring Boot 4 改用 `liteflow-spring-boot4-starter`；Solon 改用 `liteflow-solon-plugin`。通常不要自行引入 `io.agentscope:agentscope` 聚合包；若确有需要，版本必须与 LiteFlow 管理的 AgentScope `2.0.3` 一致。

### 2.2 最小配置

```properties
liteflow.rule-source=agent/flow.el.xml

# 应用名用于隔离会话数据；上线后保持稳定
spring.application.name=order-service

# DeepSeek 凭据，建议由环境变量注入
liteflow.agent.openai-compatible.deepseek.api-key=${DEEPSEEK_API_KEY}
```

应用身份配置为 `liteflow.agent.application-name`，Spring Boot 未设置时取 `spring.application.name`。纯聊天无需执行目录，组件需显式关闭默认开启的 Shell。

### 2.3 组件

```java
import com.yomahub.liteflow.agent.context.LiteFlowAgentContext;
import com.yomahub.liteflow.agent.harness.component.HarnessAgentComponent;
import com.yomahub.liteflow.agent.model.ModelSpec;
import com.yomahub.liteflow.agent.openai.DeepSeek;
import org.springframework.stereotype.Component;

@Component("chatAgent")
public class ChatAgentCmp extends HarnessAgentComponent {

    @Override
    protected ModelSpec<?> model() {
        return DeepSeek.of("deepseek-flash").stream(true);
    }

    @Override
    protected String systemPrompt() {
        return "你是一个简洁的助手，用中文回答。";
    }

    @Override
    protected String userPrompt(LiteFlowAgentContext context) {
        Object request = getSlot().getChainReqData(getSlot().getChainId());
        return request == null ? "" : request.toString();
    }

    @Override
    protected boolean enableShellTool() {
        return false;
    }
}
```

三个抽象方法必须实现：`model()`、`systemPrompt()`、`userPrompt(LiteFlowAgentContext)`。即使覆写 `buildModel()` 直接返回 AgentScope `Model`，`model()` 仍要保留一个实现。

### 2.4 EL

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE flow PUBLIC "liteflow" "liteflow.dtd">
<flow>
    <chain name="chatChain">
        THEN(chatAgent);
    </chain>
</flow>
```

### 2.5 执行

```java
LiteflowResponse response = flowExecutor.execute2Resp(
        "chatChain",
        "介绍一下 LiteFlow",
        ExecuteOption.of().autoConversationId());

if (!response.isSuccess()) {
    throw new IllegalStateException("Agent 执行失败", response.getCause());
}

Object result = response.getSlot().getResponseData();
String conversationId = response.getConversationId();
```

默认 `handleReply(...)` 把最终回复写入 `Slot.responseData`。失败原因从 `response.getCause()` 获取。

## 3. 多 Agent 编排

Agent 是普通 LiteFlow 节点，因此核心写法仍是 EL。

### 串行

```xml
<chain name="researchChain">
    THEN(searchAgent, summaryAgent, saveResultCmp);
</chain>
```

### 条件路由

条件通常由 `NodeBooleanComponent` 计算：

```xml
<chain name="routeChain">
    THEN(IF(isMathRequest, mathAgent, generalAgent));
</chain>
```

### 并行

```xml
<chain name="parallelChain">
    WHEN(agentA, agentB).maxWaitSeconds(120);
</chain>
```

Agent 默认以 nodeId 为 `agentKey`，同会话的不同节点仍受共享工作区锁协调，不能假定它们并行。但默认 `handleReply(...)` 都会清理并写入同一个 `Slot.responseData`；`WHEN(agentA, agentB)` 存在最后完成者覆盖和并发竞争。并行分支应各自只写 `setOutput(nodeId, value)`，再由串行汇总节点写最终 `responseData`。Harness 还会对同一会话的 workspace 加锁；真正并行的 Harness 任务应使用隔离的会话和 workspace。

### 把上游结果交给下游

Agent 默认只写 `responseData`，不会自动写 `slot.output[nodeId]`。流水线需要按节点取结果时，在上游覆写：

```java
@Override
protected void handleReply(Msg reply, LiteFlowAgentContext context) {
    String text = reply == null ? null : reply.getTextContent();
    getSlot().setOutput(getNodeId(), text);
    // 中间节点不调用 super，避免覆盖最终 responseData
}
```

下游读取：

```java
@Override
protected String userPrompt(LiteFlowAgentContext context) {
    Object upstream = getSlot().getOutput("searchAgent");
    return "请总结以下内容：\n" + String.valueOf(upstream);
}
```

最终节点保留默认 `handleReply(...)`，执行结束后从 `responseData` 取最终结果。

同一次 chain 执行里的多个 Agent 共享 `conversationId`，但各自用不同 `agentKey` 隔离记忆。

## 4. Agent Runtime 生命周期

Agent Runtime 在组件第一次执行时惰性创建，之后由该组件复用。以下都是**构建期能力**，不能随请求改变：

- 模型、fallback 和 routing models。
- Java 工具、内置工具、MCP 客户端和 Toolkit。
- 中间件、技能仓库和 Agent 的稳定身份。

请求级内容应放入 `userPrompt(...)`、`transformSystemPrompt(...)`、`customizeRuntimeContext(...)` 或 LiteFlow 上下文，不要保存在组件字段中。

`agentKey()` 默认返回 nodeId。它必须稳定；组件 Runtime 初始化后返回不同值会抛出 `Agent identity changed after this component runtime was initialized`。尤其不要拼入 requestId、conversationId 或租户请求参数。

Spring 和 Solon 管理的组件会随 Bean 生命周期调用 `close()`。手工创建或注册组件时，应用退出前必须关闭；关闭会等待在途调用并释放框架拥有的模型、MCP 客户端、技能仓库和 StateStore 资源。

资源所有权原则：

- `buildModel()`、`fallbackModel()`、`routingModels()` 返回的模型视为 Runtime 独占，会被关闭，不得把同一个可关闭实例交给多个组件。
- 借用 Spring Bean 时，ownership 返回 `false`；由组件独占创建时返回 `true`，让 Runtime 关闭。
- 构建失败也会回滚已创建且归 Runtime 所有的资源。

## 5. 可靠性

### 迭代、重试、回退

```java
@Override
protected int maxIterations() {
    return 20;
}

@Override
protected int maxRetries() {
    return 3;
}

@Override
protected Model fallbackModel() {
    return DashScope.of("qwen-plus").resolve(agentConfig());
}
```

- `maxIterations()` 限制一轮 Agent 调用里的“推理 → 工具 → 再推理”，全局默认 `100`。达到上限后 AgentScope 会额外调用一次模型生成摘要，并以 `GenerateReason.MAX_ITERATIONS` 返回；LiteFlow 默认 `handleReply(...)` 仍会写入该结果，不会自动让 chain 失败。业务若把达到上限视为失败，应在覆写的 `handleReply(...)` 中检查 `reply.getGenerateReason()`。
- `maxRetries()` 只作用于可重试的模型调用错误，并映射为最大尝试次数。`maxRetries() == 3` 表示首次加 2 次重试，共最多尝试 3 次；fallback 与 primary 共享这份预算。
- EL 的 `.retry(n)` 会重新执行整个节点，可能再次触发有副作用的工具；两者不能混为一谈。

### 动态路由模型

```java
@Override
protected List<Model> routingModels() {
    return List.of(cheapModel, strongModel);
}

@Override
protected Model routeModel(Model defaultModel, LiteFlowAgentContext context) {
    return isHardQuestion(context) ? strongModel : cheapModel;
}
```

### 超时和错误

- `liteflow.agent.execution-timeout` 是单次 Agent 调用总截止时间，默认 `10m`，不含等锁和首次 Runtime 构建；失败清理可能额外耗时。
- `modelExecutionConfig()` 和 `toolExecutionConfig()` 可限制内层模型和工具调用，内层超时不应大于总超时。
- `AgentConfigException` 表示配置或构建期错误，通常 fail-fast。
- `AgentInvocationException` 表示调用期错误，类型包括 `TIMEOUT`、`INTERRUPTED`、`ACQUISITION_FAILED`、`PERMISSION`、`STRUCTURED_OUTPUT`。
- 在 LiteFlow 链上统一表现为 `response.isSuccess() == false`，异常从 `getCause()` 取得。

并发守卫、StateStore 失败策略和监听器失败策略见 `agent-state-events-hitl.md`。

## 6. 本次调用上下文

动态扩展点收到的 `LiteFlowAgentContext` 可读取：

| 信息 | API |
|---|---|
| 身份 | `getNamespace()`、`getConversationId()`、`getAgentKey()` |
| 链路 | `getChainId()`、`getNodeId()`、`getRequestId()`、`getTraceId()` |
| 截止与输出 | `getDeadline()`、`getOutputSpec()`、`isCancelled()` |
| 本轮统计 | `getChatUsage()`、`getUsedSkills()`、`getConfirmationEvents()` |
| LiteFlow 数据 | `getSlot()` |

向 AgentScope 模型、工具或中间件传递请求级业务数据时：

```java
@Override
protected void customizeRuntimeContext(RuntimeContext.Builder builder,
                                       LiteFlowAgentContext context) {
    builder.put("tenantId", tenantIdFrom(context.getSlot()));
}
```

该方法每次调用执行。不要替换框架已经放入 RuntimeContext 的 `Slot` 和 `LiteFlowAgentContext`，也不能修改 sessionId 或设置 userId。

## 7. 离线测试

不调用真实模型也能验证 Spring 装配、EL、工具和输出：

```java
@Override
protected ModelSpec<?> model() {
    throw new UnsupportedOperationException("offline test uses buildModel");
}

@Override
protected Model buildModel() {
    return new FakeModel();
}
```

当前测试结构：

| 模块 | 用途 |
|---|---|
| `liteflow-testcase-el-agent-core` | core 单元和契约测试 |
| `liteflow-testcase-el-agent-harness` | Harness、filesystem、permission、sandbox 契约 |
| `liteflow-testcase-el-agent` | Spring/Solon 集成、feature、platform、真实模型测试 |

`liteflow-testcase-el-agent` 的 `ScriptedChatModel` 可按队列脚本化文本、工具调用和异常，并断言每次模型输入。`feature/*` 是离线可运行场景，`platform/*` 和 `real/*` 用于平台与真实模型验证。

## 8. 常用扩展点

| 方法 | 用途 |
|---|---|
| `buildModel()` | 直接提供 AgentScope `Model` |
| `maxIterations()` | 默认 -1 使用全局 100，覆写正数设置组件上限 |
| `maxRetries()` / `fallbackModel()` | 模型重试与回退 |
| `routingModels()` / `routeModel(...)` | 多模型路由 |
| `tools()` / `customizeToolkit(...)` | Java 工具和 Toolkit 定制 |
| `mcpClients()` / `ownsMcpClient(...)` | MCP 及资源所有权 |
| `middlewares()` | 用户中间件 |
| `enableShellTool()` | 控制内置 execute；文件工具默认可用 |
| `structuredOutputType()` / `structuredOutputSchema()` | 结构化输出，二选一 |
| `handleReply(Msg, LiteFlowAgentContext)` | 自定义最终回复去向和统计上报 |
| `resolveConversationId(Slot)` / `agentKey()` | 会话身份 |
| `stateStoreResolver()` | 自定义状态存储 |
| `permissionContext()` / `confirmationHandler()` / `stopOnReject()` | HITL |
| `skillRepositoryRegistrations()` / `skillFilter()` | Skills 仓库与过滤 |
| `transformSystemPrompt(...)` | 每次调用动态改写系统提示词 |
| `customizeRuntimeContext(...)` | 写入请求级 AgentScope 上下文 |
| `modelExecutionConfig()` / `toolExecutionConfig()` | 内层执行配置 |
| `customizeHarness(HarnessAgent.Builder)` | 最终底层定制；不得替换框架托管能力 |

`customizeHarness` 必须修改并返回原 builder，保留框架托管的模型、工具、存储、权限和文件系统。旧 `customizeAgent` 不是当前组件入口。

## 9. 启动验证与结果流

启动前把 API Key 放入实际 Java 进程的环境，执行应用的 `mvn spring-boot:run` 或已有启动方式。首轮应得到成功 response，并在 JSON 根目录产生会话文件。把 `getConversationId()` 返回调用端，再用同一 ID 调用第二轮验证续聊。

模型 `.stream(true)` 与 `ExecuteOption.eventListener(...)` 缺一不可。将 `agent.text.delta` 的文本即时交给 SSE／WebSocket；同步 Controller 只返回最终字符串不能形成流式展示。最终结果已经展示为增量时，不要再追加完整字符串。详细协议见 [agent-state-events-hitl.md](agent-state-events-hitl.md)。

可离线运行源码中的 `AgentGuideQuickStartTest`、`AgentGuideDefaultsTest`、`AgentPropertyBindingTest`，分别验证最小组件、默认配置与 Spring Boot 属性绑定。测试用脚本化模型，不需真实 API Key。
