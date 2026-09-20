> 对齐 LiteFlow `2.16.2` 与 AgentScope Java `2.0.3`。本文讲 HarnessAgentComponent 的模型和能力装配；会话、事件、执行环境与 A2A 按需读其他 reference。

# LiteFlow Agent：模型、工具、中间件与 Skills

## 1. 模型平台

所有平台通过“入口类静态工厂 + 链式参数”构造 `ModelSpec`。凭据通常放配置，模型参数放代码。

| 平台 | `model()` 中的入口 | 模块 | 配置前缀 `liteflow.agent.*` |
|---|---|---|---|
| OpenAI | `OpenAI.of("gpt-4o-mini")` | `liteflow-agent-openai` | `openai.*` |
| Anthropic | `Anthropic.of("claude-3-5-haiku-latest")` | `liteflow-agent-anthropic` | `anthropic.*` |
| Gemini | `Gemini.of("gemini-2.5-flash")` | `liteflow-agent-gemini` | `gemini.*` |
| DashScope | `DashScope.of("qwen-plus")` | `liteflow-agent-dashscope` | `dashscope.*` |
| DeepSeek | `DeepSeek.of("deepseek-chat")` | `liteflow-agent-openai` | `openai-compatible.deepseek.*` |
| Kimi | `Kimi.of("moonshot-v1-8k")` | `liteflow-agent-openai` | `openai-compatible.kimi.*` |
| GLM | `GLM.of("glm-4")` | `liteflow-agent-openai` | `openai-compatible.glm.*` |
| MiniMax | `Minimax.of("MiniMax-Text-01")` | `liteflow-agent-openai` | `openai-compatible.minimax.*` |
| 任意 OpenAI 兼容端点 | `OpenAICompatible.custom("my-platform", "model-x")` | `liteflow-agent-openai` | `openai-compatible.my-platform.*` |
| 任意 Anthropic 兼容网关 | `AnthropicCompatible.custom("gateway", "model-x")` | `liteflow-agent-anthropic` | `anthropic-compatible.gateway.*` |

模型名随平台更新，示例名称不是 LiteFlow 的固定枚举，应以用户账号实际可用模型为准。

### 凭据解析

每段支持 `api-key` 和 `base-url`：

- OpenAI、Anthropic、Gemini、DashScope：通常只配 `api-key`，未配 `base-url` 时使用官方端点。
- DeepSeek、Kimi、GLM、MiniMax：有内置默认 base URL，通常只配 key。
- `OpenAICompatible.custom(...)` 和 `AnthropicCompatible.custom(...)`：`api-key`、`base-url` 都必填，缺失会在构建期抛 `AgentConfigException`。
- 代码 `.apiKey(...)` / `.baseUrl(...)` 的显式值优先于配置。
- `extra.*` 是保留字段，2.16.2 内置 Provider 不读取；平台参数应通过 Spec API 设置。

```properties
liteflow.agent.openai.api-key=${OPENAI_API_KEY}
liteflow.agent.anthropic.api-key=${ANTHROPIC_API_KEY}
liteflow.agent.gemini.api-key=${GEMINI_API_KEY}
liteflow.agent.dashscope.api-key=${DASHSCOPE_API_KEY}

liteflow.agent.openai-compatible.deepseek.api-key=${DEEPSEEK_API_KEY}

liteflow.agent.openai-compatible.my-platform.api-key=${MY_API_KEY}
liteflow.agent.openai-compatible.my-platform.base-url=https://llm.example.com/v1
```

## 2. ModelSpec 参数

自建模型 `.contextWindow(n)` 指定真实容量，必须为正；用于长上下文压缩预算。`generateOptions(...)` 里同名生成参数优先于普通链式参数。新模型 ID 由服务决定，示例不承诺账号可用性。

### 通用参数

```java
OpenAI.of("gpt-4o-mini")
        .temperature(0.1)
        .topP(0.9)
        .topK(50)
        .maxTokens(1024)
        .seed(42L)
        .stream(true)
        .parallelToolCalls(true)
        .additionalHeader("X-Tenant", "tenant-a")
        .additionalBodyParam("custom", "value");
```

完整通用入口包括：`contextWindow`、`apiKey`、`baseUrl`、`temperature`、`topP`、`topK`、`maxTokens`、`maxCompletionTokens`、`seed`、`stream`、`cacheControl`、`parallelToolCalls`、`executionConfig(...)`、`additionalHeader(s)`、`additionalBodyParam(s)`、`additionalQueryParam(s)`、`generateOptions(...)`。

单次模型调用超时通过 `executionConfig(ExecutionConfig)` 或组件的 `modelExecutionConfig()` 设置；整个 Agent 调用的总超时是 `liteflow.agent.execution-timeout`，默认 `10m`。

### 平台特有入口

| 平台 | 特有能力 |
|---|---|
| OpenAI | `reasoningEffort`、frequency/presence penalty、endpointPath、formatter、原生结构化输出、代理、HTTP Transport、`customizeBuilder` |
| OpenAI 兼容平台 | endpointPath、`enableThinking`、代理、HTTP Transport、`customizeContext` |
| Anthropic | thinking、formatter、`customizeBuilder` |
| DashScope | thinking、formatter、原生结构化输出、代理、HTTP Transport、`customizeBuilder` |
| Gemini | thinking、formatter、`customizeBuilder` |

```java
OpenAI.of("o4-mini").reasoningEffort("medium");

Anthropic.of("claude-sonnet-4-5")
        .thinking(t -> t.enabled(true).budget(2048));

DashScope.of("qwen-plus")
        .thinking(t -> t.enabled(true).budget(512));

Gemini.of("gemini-2.5-flash")
        .thinking(t -> t.level("medium").budget(321));
```

Anthropic 开启 thinking 时 budget 必填。Gemini 新模型常用 level，旧接口可用 budget；平台是否接受某参数仍由该模型决定。

### HTTP Transport 所有权

- `.ownedHttpTransport(...)`：Transport 归 Agent Runtime，关闭或构建失败时由 Runtime 释放。
- `.borrowedHttpTransport(...)`：Transport 由调用方持有和关闭，适合共享 Bean。
- `customizeBuilder(...)` / `customizeContext(...)` 是接入平台 SDK 细节的最终入口。

不要把同一个“owned”的可关闭 Transport 或 Model 实例交给多个 Agent 组件。

### 直接提供 Model

`ModelSpec` 不足以表达自定义 SDK 或离线模型时：

```java
@Override
protected ModelSpec<?> model() {
    throw new UnsupportedOperationException("use buildModel");
}

@Override
protected Model buildModel() {
    return myModel;
}
```

`model()` 仍是抽象方法，不能省略。`buildModel()` 返回的模型被视为当前 Runtime 独占，会随 Runtime 关闭。

## 3. Java 工具

下面的组件覆写片段加入 [agent.md](agent.md) 的完整组件；仍需实现 model、systemPrompt 和 userPrompt，不能把只含 tools 的片段当成完整可编译类。

工具是普通对象，方法标注 AgentScope 的 `io.agentscope.core.tool.Tool` 和 `ToolParam`：

```java
public class OrderTool {
    @Tool(name = "query_order", description = "按订单号查询状态")
    public String queryOrder(
            @ToolParam(name = "orderId", description = "订单号") String orderId) {
        return "订单 " + orderId + " 已发货";
    }
}

@Component("orderAgent")
public class OrderAgentCmp extends HarnessAgentComponent {
    @Override
    protected List<Object> tools() {
        return List.of(new OrderTool());
    }
}
```

需要 DAO、客户端等依赖时，把工具本身注册成 Spring/Solon Bean，再注入 Agent；不要 `new` 一个需要容器注入的工具：

```java
@Component
public class OrderTool {
    @Resource
    private OrderService orderService;

    @Tool(name = "query_order", description = "按订单号查询状态")
    public String queryOrder(@ToolParam(name = "orderId") String orderId) {
        return orderService.query(orderId);
    }
}

@Component("orderAgent")
public class OrderAgentCmp extends HarnessAgentComponent {
    @Resource
    private OrderTool orderTool;

    @Override
    protected List<Object> tools() {
        return List.of(orderTool);
    }
}
```

当前 Harness 装配强制串行执行工具，`liteflow.agent.toolkit.parallel=true` 不会启用并行。模型 `.parallelToolCalls(true)` 允许生成多个调用，也不等于 LiteFlow 并行执行这些调用。工具若被多个会话复用仍需线程安全。

只有带 `@ToolParam` 的参数会进入提供给模型的工具 Schema；`name` 必填，`required` 默认 `true`。`required=false` 缺参时值为 `null`，所以可选数值／布尔参数应使用包装类型，不能使用不能接收 `null` 的基本类型。

未标注参数不会让模型填写，只适合 AgentScope 自动注入的 `ToolEmitter`、`Agent`、`AgentState`、`RuntimeContext`、旧 `ToolExecutionContext`，或能从 `RuntimeContext` 按类型取得的对象。普通字符串、集合、基本类型等业务入参忘记标注时，既不进 Schema，也不能可靠接收模型参数。

`AgentState` 注入还要求方法标注 `@Tool(stateInjected = true)`，对应参数不能再标 `@ToolParam`。不能依靠 Toolkit 串行设置隔离多个并发会话的共享业务状态。

工具方法只有在**声明返回类型**恰为 `Mono<T>` 或 `CompletableFuture<T>` 时才会异步展开；`Flux`、`Future`、`CompletionStage`、其他 Publisher 或自定义 future 都不支持自动展开。参数、方法、异步或超时错误通常会变成 `ToolResultBlock.error` 交给模型处理，不会直接让 LiteFlow chain 失败；取消会向异步调用传播，但不能保证已开始的同步阻塞或外部副作用停止。

AgentScope 工具默认单次超时 5 分钟、最多尝试 1 次，而 LiteFlow Agent 总 deadline 默认 10 分钟，应按实际内外超时判断谁先取消。生产配置应让工具／模型内层超时不大于 `liteflow.agent.execution-timeout`。

## 4. 内置文件与 Shell 工具

2.16.2 统一使用 Harness 文件工具：`read_file`、`write_file`、`edit_file`、`list_files`、`grep_files`、`glob_files`，默认可用；Shell 名为 `execute`，默认开启。纯聊天组件覆写 `enableShellTool()` 返回 false。

开启本地 Shell 时设置 `harness.local.workspace-root`；Docker 选择 `harness.filesystem-backend=DOCKER` 并配置镜像和存储。旧 `enableWorkspaceFileTools()`、`workspace.root`、`execute_shell_command` 不是当前接入方式。六种存储／执行组合、白名单、命令超时和附件交付见 [agent-harness.md](agent-harness.md)。

## 5. MCP 工具

下面组件同样只展示追加字段与方法，保留最小组件的三个必要方法。

支持 Streamable HTTP、SSE 和 stdio transport。下面由 Spring 持有客户端，Agent 只借用：

```java
@Configuration
public class McpConfig {
    @Bean(destroyMethod = "close")
    public McpClientWrapper weatherMcpClient() {
        return McpClientBuilder.create("weather")
                .streamableHttpTransport("https://mcp.example.com/mcp")
                .header("Authorization", "Bearer " + System.getenv("MCP_TOKEN"))
                .buildSync();
    }
}

@Component("weatherAgent")
public class WeatherAgentCmp extends HarnessAgentComponent {
    @Resource
    private McpClientWrapper weatherMcpClient;

    @Override
    protected List<McpClientWrapper> mcpClients() {
        return List.of(weatherMcpClient);
    }
}
```

首次构建 Runtime 时，LiteFlow 初始化客户端、发现远端工具并注册到 Toolkit。

所有权：

- 默认 `ownsMcpClient(client) == false`，调用方或 Spring 关闭，适合共享。
- 返回 `true` 表示由当前 Runtime 独占，Runtime 关闭或构建失败时释放，不能再跨组件共享。

`customizeToolkit(Toolkit)` 在 Java 工具和内置工具装配后执行，但 MCP 工具在该回调之后才注册，所以回调中看不到 MCP 工具。

## 6. 中间件

实现 AgentScope `MiddlewareBase`，在组件中返回：

```java
@Override
protected List<MiddlewareBase> middlewares() {
    return List.of(new MiddlewareBase() {
        @Override
        public Flux<AgentEvent> onAgent(
                Agent agent,
                RuntimeContext runtimeContext,
                AgentInput input,
                Function<AgentInput, Flux<AgentEvent>> next) {
            return next.apply(input)
                    .doOnComplete(() -> metrics.increment());
        }
    });
}
```

可按需覆写 `onAgent`、`onReasoning`、`onActing`、`onModelCall`、`onSystemPrompt` 等切点。返回 `Flux.error(...)` 会阻断调用并让链失败。

框架自动安装日志、状态持久化、事件桥接等内置中间件。所有用户中间件统一放在 `order=1000` 层，用户对象自己的 `order()` 不参与最终排序；多个用户中间件按 `middlewares()` 列表顺序执行。

2.16.2 不再使用旧 `hooks()`、Hook priority 或 `enableReActLogging()`；执行过程日志开关是 `liteflow.agent.execution-log-enabled`，默认 `true`，使用默认值时无需配置。

## 7. Skills

技能是目录中的 `SKILL.md`：

```markdown
---
name: order-query
description: 当用户查询订单状态时使用
---

# 订单查询

先确认订单号，再调用只读查询工具。
```

最小配置：

```properties
liteflow.agent.skills.enabled=true
liteflow.agent.skills.path=./skills

# classpath 资源也支持
# liteflow.agent.skills.path=classpath:agent/skills
```

LiteFlow 根据路径创建 Repository，并在 Runtime 关闭或构建失败时自动释放。普通路径是文件系统目录，`classpath:` 是应用资源。

自定义或共享 Repository 时：

```java
@Override
protected List<SkillRepositoryRegistration> skillRepositoryRegistrations() {
    return List.of(
            SkillRepositoryRegistration.owned(privateRepository),
            SkillRepositoryRegistration.borrowed(sharedRepository));
}

@Override
protected SkillFilter skillFilter() {
    return SkillFilter.only("order-query", "refund-policy");
}
```

- `owned` 随 Runtime 关闭，`borrowed` 由调用方关闭。
- `context.getUsedSkills()` 可在 `handleReply(...)` 中读取本轮实际使用的技能。
- `dynamicSkillsEnabled()` 默认 `true`，负责安装动态技能中间件；只有自行接管装配时才关闭。
- `liteflow.agent.skills.strict` 在 2.16.2 只是兼容保留项，不改变解析或失败策略。
- 旧版 Skill frontmatter `tools:`、`SkillToolResolver`、`skills()` 白名单、`enableSkills()` 不属于 2.16.2 API。
- 技能说明和 scripts／references／assets 会准备到会话 `.skills-cache/`。脚本执行需要 Shell 开启、白名单允许且解释器已安装；业务输出不要放入框架会更新的技能缓存。
- `skills.path` 始终从 Java 应用环境读取，Docker 模式也不改成容器路径。文件系统技能在后续调用重新发现；classpath 资源变化需重建部署。`dynamicSkillsEnabled(false)` 固定技能集合。
- frontmatter 的 name、description 与正文必须非空；技能中提到的 Java／MCP 工具仍需注册。

## 8. 常见排查

| 症状 | 原因和处理 |
|---|---|
| compatible 平台缺凭据 | 自定义 compatible 的 api-key/base-url 都要配；预设平台通常只需 key |
| `enableShellTool requires ...` | 设 `harness.shell.mode=WHITELIST`，提供非空白名单 |
| 本地 Shell 提示目录缺失 | 配置 `harness.local.workspace-root`，或关闭 Shell |
| 工具依赖为 `null` | 工具被手工 `new`，改成容器 Bean 后注入 Agent |
| MCP 连接泄漏或重复关闭 | 明确 `ownsMcpClient`，共享 Bean 用 borrowed 语义 |
| 中间件顺序与 `order()` 不一致 | 用户中间件只按返回列表顺序，统一 order 1000 |
| `skills.strict` 没效果 | 该配置是兼容占位，不控制严格模式 |
| 修改工具/模型后不生效 | Runtime 已构建并复用；重建组件/应用，不要把构建期配置做成请求动态值 |
