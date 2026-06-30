> 来源：LiteFlow 官方文档 `liteflow-homepage/docs/06.AI Agent编排/`（010 什么是ReAct Agent / 020 快速开始[引入依赖·基本配置·编写Agent组件·获取结果·流式输出] / 030 模型配置 / 040 会话与记忆 / 050 工作空间与工具 / 060 Skills / 070 高级编排 / 080 运行机制与可观测 / 090 扩展点速查 / 100 配置速查 / 110 安全建议 / 120 故障排查 / 130 演示项目），并以源码 `liteflow-react-agent/`（`ReActAgentComponent` / `ModelSpec` / 各平台入口类 / `AgentSessionManager`）核对类名与方法签名。
>
> ⚠️ **版本/状态说明**：AI Agent 编排是 LiteFlow 的**独立扩展模块** `liteflow-react-agent`，文档在 `06.AI Agent编排`（**不在** `04.v2.16.X文档` 主线里），属较新特性、仍在演进；本文坐标按官方示例的 `2.16.0` 给出。**模型名（如 `deepseek-v4-flash`、`claude-sonnet-4-5`）随各厂商更新，请以你账号下可用模型为准。** 拿不准的方法/配置按 SKILL.md 决策流程实地查 `liteflow-react-agent/` 源码，勿臆造。

# LiteFlow ReAct Agent（AI Agent 编排）

把 **AI Agent 当成一个 LiteFlow 组件**编排进 EL 规则——Agent 节点可与普通业务节点用 `THEN`/`WHEN`/`IF`/`SWITCH` 自由组合。底层封装的是 [agentscope-java](https://github.com/agentscope/agentscope-java) 的 `ReActAgent`（Reasoning + Acting 循环：推理→调用工具→观察→继续推理，直到得出最终答案）。

---

## 一、模块组成与依赖

聚合模块 `liteflow-react-agent`，按模型平台拆子模块；业务项目**通常只引一个平台模块**（会自动传递 `liteflow-react-agent-core`）。

| 模块 | 作用 / 入口类 |
|---|---|
| `liteflow-react-agent-core` | 核心：`ReActAgentComponent`、`ModelSpec`、会话/Memory、流式事件、Workspace 文件工具、Shell 工具 |
| `liteflow-react-agent-openai` | OpenAI + OpenAI 兼容协议；入口 `OpenAI` / `DeepSeek` / `Kimi` / `GLM` / `Minimax` / `OpenAICompatible` |
| `liteflow-react-agent-anthropic` | Anthropic Claude；入口 `Anthropic` / `AnthropicCompatible` |
| `liteflow-react-agent-gemini` | Google Gemini；入口 `Gemini` |
| `liteflow-react-agent-dashscope` | 阿里云 DashScope / Qwen；入口 `DashScope` |

```xml
<!-- 以 DeepSeek（OpenAI 兼容）为例 -->
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-react-agent-openai</artifactId>
    <version>2.16.0</version>
</dependency>
```

**前提**：业务应用仍需引入 LiteFlow 运行集成（如 `liteflow-spring-boot-starter`）；**JDK 17+**；要用多个平台就引多个平台模块。

---

## 二、最小可运行示例

### 1. 配置（`liteflow.agent.*`）

```properties
liteflow.rule-source=agent/flow.el.xml

# Workspace 根目录——必填！未配置首次执行 Agent 会抛 AgentConfigException: liteflow.agent.workspace.root is required
liteflow.agent.workspace.root=/var/lib/liteflow/agent-workspaces

# 生产建议默认关闭 Shell 工具
liteflow.agent.shell.mode=DISABLED

# 模型凭据（DeepSeek 走 openai-compatible.<configKey>）
liteflow.agent.openai-compatible.deepseek.api-key=${DEEPSEEK_API_KEY}
liteflow.agent.openai-compatible.deepseek.base-url=https://api.deepseek.com/v1
```

> `workspace.root` 支持绝对/相对路径（相对基于 JVM 的 `user.dir`）。**生产一律用绝对路径**——`user.dir` 在 IDE / `java -jar` / systemd / 容器下差异巨大。

### 2. 写一个 Agent 组件（继承 `ReActAgentComponent`）

`process()` 是 **`final`**：框架统一做配置读取、会话解析、Session 取用、加锁、Agent 构建、调用、回复处理、Memory 保存。业务侧只覆写受保护方法。**至少实现 3 个抽象方法**：

```java
@Component("deepseekAgent")
public class DeepSeekAgentCmp extends ReActAgentComponent {

    @Override
    protected ModelSpec<?> model() {                 // 声明用哪个平台、哪个模型
        return DeepSeek.of("deepseek-chat");
    }

    @Override
    protected String systemPrompt() {                // 系统提示词（同一 Session 首次构建时调用）
        return "你是一名简洁的中文助理，回答控制在两句话以内。";
    }

    @Override
    protected String userPrompt() {                  // 用户消息（每次调用都执行）
        Object req = getSlot().getChainReqData(getSlot().getChainId());
        return req == null ? "" : req.toString();
    }
}
```

> ⚠️ **你的 `systemPrompt()` 不是最终系统提示词**：框架始终在它前面拼一段内置统一提示词（最终 = `内置提示词 + "\n\n" + 你的 systemPrompt()`）。内置提示词约定了默认行为：默认用用户提问语言回答（要固定语言需自己在 `systemPrompt()` 显式覆盖）；每次调工具前先输出一两句推理摘要（即流式 `agent.reasoning` 事件/ReAct 日志里的简短推理，属预期行为）。

### 3. EL 中编排（Agent 节点 = 普通节点）

```xml
<chain name="deepseekChain">
    THEN(prepare, deepseekAgent, recordReply);
</chain>
```
```xml
IF(isMath, mathAgent, deepseekAgent);              <!-- 条件路由选 Agent -->
WHEN(deepseekAgent, qwenAgent).maxWaitSeconds(60); <!-- 多模型并行 -->
THEN(prepare, WHEN(analyzerAgent, riskAgent), summaryAgent, notify);
```

### 4. 取结果

```java
LiteflowResponse response = flowExecutor.execute2Resp("deepseekChain", "用一句话介绍 LiteFlow");
if (response.isSuccess()) {
    Object reply = response.getSlot().getResponseData();   // 默认：Agent 文本回复写入 slot.responseData
}
```

下游节点直接读 `this.getSlot().getResponseData()`。**链路里有多个 Agent 时**，`responseData` 是 slot 级单字段、后写覆盖先写——务必覆写 `handleReply` 按 nodeId 区分：

```java
@Override
protected void handleReply(Msg reply) {                    // Msg = io.agentscope 的消息对象
    String text = reply == null ? null : reply.getTextContent();
    ctx().getSlot().setOutput(getNodeId(), text);          // 以 nodeId 为 key 存入 slot
    // 或：ctx().getSlot().getContextBean(MyAgentCtx.class).setReply(getNodeId(), text);
}
```

---

## 三、模型配置（ModelSpec）

`ModelSpec<SELF>` 是所有平台模型描述符基类，三段式："平台入口类 `.of("模型名")` + 链式可选参数"。**逃生舱**：覆写 `buildModel()` 可直接构造 agentscope 原生 `Model`（此时 `model().resolve(...)` 不再调用，但 `model()` 仍须实现）。

**共性参数**（均可选）：`temperature(double)` / `topP(double)` / `topK(int)` / `maxTokens(int)` / `seed(long)` / `stream(boolean)` / `cacheControl(boolean)`。

| 平台入口类 | 个性参数 | 凭据配置路径 |
|---|---|---|
| `OpenAI.of(model)` | `reasoningEffort` / `frequencyPenalty` / `presencePenalty` | `liteflow.agent.openai.api-key` |
| `DeepSeek`/`Kimi`/`GLM`/`Minimax` `.of(model)` | 继承 OpenAI，内置默认 baseUrl | `liteflow.agent.openai-compatible.<configKey>.api-key`（`base-url` 可选） |
| `OpenAICompatible.custom("vendor","model")` | 任意 OpenAI 兼容厂商 | `liteflow.agent.openai-compatible.vendor.api-key` / `.base-url`（自定义厂商通常需配 base-url） |
| `Anthropic.of(model)` | `thinking(t -> t.budget(n).enabled(true))` | `liteflow.agent.anthropic.api-key` |
| `Gemini.of(model)` | `thinking(t -> t.level("high").budget(n))` | `liteflow.agent.gemini.api-key` |
| `DashScope.of(model)` | `thinking(t -> t.budget(n))` | `liteflow.agent.dashscope.api-key` |

凭据解析两类策略：**头等平台**（OpenAI/Anthropic/Gemini/DashScope）从单一字段读 `liteflow.agent.<platform>.api-key`；**兼容平台**（DeepSeek/Kimi/GLM/Minimax/自定义）按 configKey 从 Map 读 `liteflow.agent.openai-compatible.<configKey>.api-key`。

```java
@Override protected ModelSpec<?> model() {
    return Anthropic.of("claude-sonnet-4-5").temperature(0.5)
            .thinking(t -> t.budget(2000).enabled(true));
}
```

---

## 四、`ReActAgentComponent` 可覆写方法（扩展点速查）

| 方法 | 必须 | 默认 | 说明 |
|---|---|---|---|
| `model()` | ✅ | — | 返回 `ModelSpec<?>` |
| `systemPrompt()` | ✅ | — | 系统提示词；**同一 Session 首次构建时调用**（构建期能力，别依赖单次请求数据） |
| `userPrompt()` | ✅ | — | 本轮用户消息；每次 `process()` 都调用（**动态输入放这里**） |
| `tools()` | 否 | 空 | 注册自定义 `@Tool` 对象（见第五节） |
| `handleReply(Msg)` | 否 | 写 `slot.responseData` | 自定义回复落点（多 Agent 必覆写） |
| `maxIterations()` | 否 | `-1` | 返回正数覆盖全局最大迭代次数 |
| `enableShellTool()` | 否 | `true` | 是否注册内置 Shell 工具 |
| `enableWorkspaceFileTools()` | 否 | `true` | 是否注册内置文件工具 |
| `hooks()` | 否 | 空 | 注册 agentscope `Hook` |
| `enableReActLogging()` | 否 | 读全局配置 | 是否注册内置 ReAct 日志 Hook |
| `skills()` / `enableSkills()` | 否 | 空 / 全局 | Skills 技能白名单 / 开关 |
| `resolveConversationId()` | 否 | 先复用 slot→读请求→自动生成 | 决定本次调用所属业务会话 |
| `agentKey()` | 否 | 当前 `nodeId` | 同一 conversation 内区分不同 Agent |
| `buildModel()` | 否 | 委派 `model().resolve()` | 完全自定义底层 Model（逃生舱） |

`ctx()`（返回 `ReActAgentContext`，**仅能在 `process()` 生命周期内调用**——含 `systemPrompt()`/`userPrompt()`/工具回调/Hook/`handleReply()`；**勿在构造器或异步线程调用**）：`getSlot()` / `getConversationId()` / `getAgentKey()` / `getWorkspaceDir()` / `getChatUsage()`（token 用量，需本轮 reasoning step 完成后才非 null，建议在 `handleReply()` 读）。

> 关键约束：`systemPrompt()`/`tools()`/`hooks()`/`skills()` 是 Agent **构建期能力声明**，只在 `(conversationId, agentKey)` 首次构建缓存 Agent 时生效。要按请求隔离，就把请求维度体现在 `agentKey()` / `resolveConversationId()` 里，别让构建期方法依赖单次请求数据。

---

## 五、自定义工具（`@Tool`）

工具是普通 Java 对象，方法用 agentscope 的 `@Tool` / `@ToolParam` 注解，再在组件里覆写 `tools()` 注册：

```java
import io.agentscope.core.tool.Tool;
import io.agentscope.core.tool.ToolParam;

public class OrderTool {
    @Tool(name = "query_order_status", description = "Query order status by order number")
    public String query(@ToolParam(name = "orderNo") String orderNo) {
        return "订单 " + orderNo + " 正在处理中";
    }
}
```
```java
@Override protected List<Object> tools() { return List.of(new OrderTool()); }
```

**工具内要访问 Slot/workspace/会话**：不要在构造工具时捕获 `ctx()` 返回值（工具会被缓存复用）。推荐①把工具写成组件**内部类**，回调里 `ctx().getSlot()`；或②给组件加公开代理方法、工具持有组件实例再间接调 `ctx()`。

---

## 六、流式输出

`execute2Resp(...)` 仍是阻塞调用（整条 chain 执行完才返回）。要在 Agent 执行过程中实时拿输出，用 `ExecuteOption.eventListener(...)` 注册监听器；要让**底层模型请求**也走流式，再在 `model()` 上 `.stream(true)`（两者各管一层，配合使用）。

```java
LiteflowResponse response = flowExecutor.execute2Resp(
    "deepseekChain", "用一句话介绍 LiteFlow",
    ExecuteOption.of()
        .conversationId("chat-user-1-conv-1")
        .eventListener(event -> {
            if ("agent.reasoning".equals(event.getType()) && event.getText() != null) {
                System.out.print(event.getText());   // 转发到 SSE / WebSocket / CLI
            }
        }));
```

**事件类型** `FlowEvent#getType()`：`agent.reasoning`（推理/回复增量、最终消息、工具调用请求）、`agent.tool_result`（工具结果）、`agent.summary`（达到最大迭代后的总结）、`agent.result`（本轮最终结果，与 `handleReply` 一致）。`FlowEvent` 字段：`chainId/nodeId/requestId/conversationId/text/last/timestamp/data`。

注意：未注册 listener 时走阻塞路径、零额外开销；listener 是**同步回调**，跑在 chain 执行线程——生产里只做轻量入队，别做耗时 I/O，且 **listener 抛异常会向上传播导致链路失败**。`WHEN` 多 Agent 并发时事件会交错，按 `nodeId` 分组展示。

---

## 七、会话 / 记忆 / Workspace / Shell / Skills 配置速查

```properties
# Workspace
liteflow.agent.workspace.root=/var/lib/liteflow/agent-workspaces   # 必填
liteflow.agent.workspace.auto-create=true
liteflow.agent.workspace.cleanup-on-session-expire=true
liteflow.agent.workspace.max-file-bytes=10485760
# 热 Session 缓存
liteflow.agent.session.idle-timeout=30m
liteflow.agent.session.max-sessions=10000
# Memory 持久化：mode=JVM(默认)/LOCAL_FILE/REDIS/MYSQL
liteflow.agent.session.memory.mode=JVM
liteflow.agent.session.memory.save-after-call=true
liteflow.agent.session.memory.redis.bean-name=redissonClient        # mode=REDIS
liteflow.agent.session.memory.mysql.data-source-bean-name=agentDataSource  # mode=MYSQL
# Shell 工具：mode=DISABLED/WHITELIST/...
liteflow.agent.shell.mode=WHITELIST
liteflow.agent.shell.timeout=30s
# ReAct 日志 / 最大迭代
liteflow.agent.logging.react-enabled=true
liteflow.agent.defaults.max-iterations=50
# Skills 技能系统
liteflow.agent.skills.enabled=false
liteflow.agent.skills.path=./skills
```

多轮对话：同一 `conversationId` 复用 Session 与记忆；Memory 模式决定记忆存哪（JVM 内存 / workspace 下的 `.agent-session/<sessionId>/` 本地文件 / Redis / MySQL）。

---

## 八、常见坑

- **`workspace.root` 必填**，否则首次执行 Agent 抛 `AgentConfigException: liteflow.agent.workspace.root is required`；生产用绝对路径。
- **`process()` 是 final**，业务逻辑只能通过覆写受保护方法实现，别想覆盖 `process()`。
- **`systemPrompt()` 会被加前缀**——不是最终系统提示词；要固定回复语言须自己显式覆盖。
- **多 Agent 链路必覆写 `handleReply`**：默认 `responseData` 后写覆盖先写。
- **构建期方法（systemPrompt/tools/hooks/skills）只在首次构建缓存生效**，别依赖单次请求数据；按请求隔离改用 `agentKey()` / `resolveConversationId()`。
- **工具/Hook/Model 会被缓存复用**，别在里面保存某次 `ctx()` 引用；运行时通过组件间接 `ctx()`。
- **流式 listener 是同步回调**，只做轻量入队，抛异常会让链路失败。
- **JDK 17+**；模型名随厂商更新，以你账号可用模型为准。
