> 来源：LiteFlow 官方文档 `liteflow-homepage/docs/06.AI Agent编排/`（010 什么是ReAct Agent / 020 快速开始[引入依赖·基本配置·编写Agent组件·获取结果·流式输出] / 030 模型配置 / 040 会话与记忆 / 050 工作空间与工具 / 060 Skills / 070 高级编排 / 080 运行机制与可观测 / 090 扩展点速查 / 100 配置速查 / 110 安全建议 / 120 故障排查 / 130 演示项目），并以源码 `liteflow-react-agent/`（`ReActAgentComponent` / `ModelSpec` / 各平台入口类 / `AgentSessionManager` / `SkillBoxFactory` / `SkillToolResolver` / `WorkspaceFileTools` / `ManagedShellCommandTool` / `AgentSessionFactory` 及 `liteflow-core` 的 `property/agent/*Config`）核对类名、方法签名与配置默认值。
>
> ⚠️ **版本/状态说明**：AI Agent 编排是 LiteFlow 的**独立扩展模块** `liteflow-react-agent`，文档在 `06.AI Agent编排`（**不在** `04.v2.16.X文档` 主线里），属较新特性、仍在演进；本文坐标按当前源码 HEAD revision `2.16.1.1`（v2.16.1 tag 之上的 javax-pro 修复版）给出。**模型名（如 `deepseek-v4-flash`、`claude-sonnet-4-5`）随各厂商更新，请以你账号下可用模型为准。** 拿不准的方法/配置按 SKILL.md 决策流程实地查 `liteflow-react-agent/` 源码，勿臆造。

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
    <version>2.16.1</version>
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
| `AnthropicCompatible.custom("<configKey>","<model>")` | Anthropic 兼容网关/代理 | `liteflow.agent.anthropic-compatible.<configKey>.api-key` / `.base-url`（通常需配 base-url） |
| `Gemini.of(model)` | `thinking(t -> t.level("high").budget(n))` | `liteflow.agent.gemini.api-key` |
| `DashScope.of(model)` | `thinking(t -> t.budget(n))` | `liteflow.agent.dashscope.api-key` |

凭据解析两类策略：**头等平台**（OpenAI/Anthropic/Gemini/DashScope）从单一字段读 `liteflow.agent.<platform>.api-key`；**兼容平台**按 configKey 从 Map 读——OpenAI 兼容走 `liteflow.agent.openai-compatible.<configKey>.api-key`（DeepSeek/Kimi/GLM/Minimax/`OpenAICompatible.custom`），Anthropic 兼容走 `liteflow.agent.anthropic-compatible.<configKey>.api-key`（`AnthropicCompatible.custom`）。

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

**Spring/Solon 下需要依赖注入的工具**：工具若依赖容器 bean（DAO、远程客户端等），应把工具类标 `@Component` 由容器注入依赖，再在 Agent 组件里用 `@Resource`/`@Autowired` 注入该工具 bean 后放进 `tools()`——**不要 `new` 需要 DI 的工具类**，那样注入不会生效。`ReActAgentComponent` 本身就是容器 bean，字段天然由容器管理。这与 skill frontmatter `tools:`（见第六节）不同：后者写的是类名，由框架 `SkillToolResolver` 按类型从容器查找（DI 生效），找不到才反射兜底；而 `tools()` 返回的是对象实例，获取实例的工作由开发者完成。

---

## 六、Skills 技能系统

Skills 是 AgentScope 的 filesystem skills 机制：在 `liteflow.agent.skills.path` 下放 `SKILL.md` 描述"何时用、怎么做"的长指令，并可选地把某些 Java `@Tool` 只绑定到指定 skill（避免所有工具全局暴露给 Agent）。默认关闭。

### 1. 开启与配置三键

```properties
liteflow.agent.skills.enabled=true       # 默认 false
liteflow.agent.skills.path=./skills      # skills 根目录，每个子目录一个 skill
liteflow.agent.skills.strict=true        # 默认 true，严格模式
```

| 配置项 | 默认 | 说明 |
|---|---|---|
| `skills.enabled` | `false` | 是否启用 skills 支持 |
| `skills.path` | `./skills` | skills 根目录（绝对/相对，相对基于 JVM `user.dir`；**生产用绝对路径**，与 `workspace.root` 同理） |
| `skills.strict` | `true` | 严格模式：目录缺失或白名单含不存在技能时快速失败；`false` 降级为 warn |

strict 行为（源码 `SkillBoxFactory`）：`skills.path` 不是目录时，strict 抛 `AgentConfigException: Skills root not found: ...`，非 strict 仅 warn 并返回空 SkillBox；`skills()` 声明的技能在目录里找不到时，strict 抛 `Declared skills not found: [...]`，非 strict warn 后跳过缺失项。

### 2. 目录结构与 SKILL.md frontmatter

```
skills/
├── demo/
│   └── SKILL.md
└── tool-skill/
    └── SKILL.md
```

最小 `SKILL.md`：

```markdown
---
name: demo
description: Demo skill for LiteFlow ReAct agent
---

# Demo Skill

Use this skill when the request is about a simple demonstration.
```

`name` 是组件 `skills()` 过滤用的技能名，**建议目录名与 `name` 保持一致**。

### 3. 组件级白名单 `skills()`

```java
@Override
protected List<String> skills() {
    return List.of("demo", "tool-skill");
}
```

- 返回**空列表**：允许 `skills.path` 下的全部技能
- 返回**非空列表**：只把这些技能放入本 Agent 的 SkillBox（白名单）
- 是**构建期能力声明**，只在 `(conversationId, agentKey)` 首次构建缓存 Agent 时生效（同 `tools()`/`systemPrompt()`，别依赖单次请求数据）

也可在全局开启后对单个组件禁用：

```java
@Override protected boolean enableSkills() { return false; }
```

### 4. Skill 专属 Java 工具（frontmatter `tools:`）

在 `SKILL.md` frontmatter 用全限定类名声明只随该 skill 可用的工具：

```markdown
---
name: tool-skill
description: Skill that binds a Java tool
tools: com.example.agent.tool.SkillEchoTool
---
```

`tools` 支持 YAML 单值 / 逗号分隔 / 行内数组（`[a, b]`）/ 块列表（多行 `- a`）四种写法。解析由 `SkillToolResolver` 完成，顺序如下：

- **优先按类型从框架容器（Spring/Solon）取 bean**——依赖注入生效（`contextAware.hasBean(clazz)` → `getBean(clazz)`）
- 容器中无此类型、容器未就绪或获取异常时，**降级为反射调无参构造器**（此时 DI 不可用）
- 工具方法仍按 agentscope `@Tool` / `@ToolParam` 声明，工具类必须在 classpath 上（推荐注册为容器 bean，否则至少提供公有无参构造器兜底）

### 5. 记录本轮使用的技能 `usedSkills()`

`usedSkills()` 返回当前 invocation 中已成功加载（`load_skill_through_path`）的技能名列表；每次 `process()` 开始前清空，**仅在 `process()` 生命周期内**（如 `handleReply()`）可读：

```java
@Override
protected void handleReply(Msg reply) {
    ctx().getSlot().setOutput(getNodeId(), Map.of(
            "reply", reply == null ? "" : reply.getTextContent(),
            "skillsUsed", usedSkills()
    ));
}
```

### 6. ⚠️ 安全红线：开启 skills = 开启独立代码执行路径

开启 skills 后，框架会在 conversation workspace 内启用 AgentScope 的代码执行能力（`SkillBoxFactory.createSkillBox` 中 `workspaceDir` 非空即 `skillBox.codeExecution().workDir(...).enable()`）。这条路径走 AgentScope 自身执行通道，**独立于 `liteflow.agent.shell.*`**——即使把 `shell.mode` 设为 `DISABLED`，开启 skills 后代码执行路径依然存在，也不受 Shell 白名单/黑名单约束。**生产开启前必须评估此路径的安全影响，并严格管控 `skills.path` 及其引用 Java 工具类的来源。**

---

## 七、流式输出

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

### 自定义 Hook（底层事件拦截，区别于 eventListener）

`hooks()` 注册的是 agentscope 的 `io.agentscope.core.hook.Hook`——比上层 `FlowEvent`/`eventListener` 更底层的事件拦截点，能拿到原始推理消息、工具调用块、token 用量等结构化数据。两者是两层：`eventListener` 面向"把过程推给前端"，Hook 面向审计/埋点/事件改写。

```java
public interface Hook {
    <T extends HookEvent> Mono<T> onEvent(T event);   // 放行 return Mono.just(event)
    default int priority() { return 100; }            // 默认 100，内置日志 Hook 用 900
}
```

按 `instanceof` 分发事件类型（`io.agentscope.core.hook.*`）：`PreReasoningEvent`/`PostReasoningEvent`/`ReasoningChunkEvent`、`PreActingEvent`/`PostActingEvent`/`ActingChunkEvent`、`PreSummaryEvent`/`PostSummaryEvent`、`PreCallEvent`/`PostCallEvent`、`ErrorEvent`（Summary 系列仅当达到 `maxIterations` 强制收尾时触发）。

自定义 `hooks()` 与框架内置 Hook **合并后按 `priority()` 排序**执行——内置包括 `ReActLoggingHook`（写 reason/act/error 日志，开关 `enableReActLogging()`/`logging.react-enabled`）、`ChatUsageTrackingHook`（收 token 用量供 `ctx().getChatUsage()` 读，始终启用）、`SkillTrackingHook`（记 `usedSkills()`，开启 skills 时启用）。约束：`hooks()` 是构建期能力声明（同 `tools()`/`systemPrompt()`，只首次构建生效）；Hook 会被缓存复用，**勿持有 `ctx()` 引用**、勿阻塞、勿抛异常（自行 try/catch，框架内置 Hook 即如此）。内置 ReAct 日志 logger 名为 `com.yomahub.liteflow.agent.hook.ReActLoggingHook`，可独立调级，文本字段超 500 字截断为 `...(truncated)`。

---

## 八、会话 / 记忆 / Workspace / Shell / Skills 配置速查

```properties
# Workspace
liteflow.agent.workspace.root=/var/lib/liteflow/agent-workspaces   # 必填
liteflow.agent.workspace.auto-create=true
liteflow.agent.workspace.cleanup-on-session-expire=true
liteflow.agent.workspace.cleanup-on-jvm-shutdown=false
liteflow.agent.workspace.max-file-bytes=10485760                   # read_file 单次最大字节
liteflow.agent.workspace.max-list-size=1000                        # list_files 单次最大条目
# 热 Session 缓存（只管 JVM 内热实例留存，与 memory 持久化是两件事）
liteflow.agent.session.idle-timeout=30m
liteflow.agent.session.cleanup-interval=1m
liteflow.agent.session.max-sessions=10000
# Memory 持久化：mode=JVM(默认)/NONE/LOCAL_FILE/REDIS/MYSQL
liteflow.agent.session.memory.mode=JVM
liteflow.agent.session.memory.load-on-first-use=true               # 首次构建尝试恢复历史
liteflow.agent.session.memory.save-after-call=true
liteflow.agent.session.memory.save-on-error=true                   # 调用抛错也尝试保存
# REDIS：client-type=REDISSON/JEDIS/LETTUCE（默认 REDISSON，bean 类型须匹配）
liteflow.agent.session.memory.redis.bean-name=redissonClient
liteflow.agent.session.memory.redis.client-type=REDISSON
liteflow.agent.session.memory.redis.key-prefix=liteflow:agent:session
# MYSQL
liteflow.agent.session.memory.mysql.data-source-bean-name=agentDataSource
liteflow.agent.session.memory.mysql.database-name=agentscope
liteflow.agent.session.memory.mysql.table-name=agentscope_sessions
liteflow.agent.session.memory.mysql.create-if-not-exist=false
# Shell 工具：默认 WHITELIST（即默认开启！），生产建议 DISABLED 或收窄白名单
liteflow.agent.shell.mode=WHITELIST
liteflow.agent.shell.whitelist=ls,find,cat,grep,...                # 默认白名单含 curl/wget/python3/node
liteflow.agent.shell.blacklist=rm,sudo,shutdown,mkfs,dd,...
liteflow.agent.shell.timeout=30s
liteflow.agent.shell.max-output-bytes=1048576                       # 1MB
# ReAct 日志 / 最大迭代
liteflow.agent.logging.react-enabled=true
liteflow.agent.defaults.max-iterations=50
# Skills 技能系统（详见六）
liteflow.agent.skills.enabled=false
liteflow.agent.skills.path=./skills
liteflow.agent.skills.strict=true
```

**记忆持久化**：同一 `conversationId` 复用 Session 与记忆；`memory.mode` 决定记忆存哪——`JVM`（内存，重启丢）/ `NONE`（不加载也不保存，严格无状态）/ `LOCAL_FILE`（`workspace.root/.agent-session/`）/ `REDIS`（多实例共享）/ `MYSQL`。通用开关 `load-on-first-use`/`save-after-call`/`save-on-error` 默认均 `true`。**热 Session 缓存**（`idle-timeout`/`cleanup-interval`/`max-sessions`）只管 JVM 内热 Agent 实例的留存与淘汰，淘汰不删 workspace 和持久化记忆——和 memory 持久化是两件事。REDIS 模式 `client-type` 的 bean 类型须与 `bean-name` 指向的 bean 匹配，否则启动失败抛 `AgentConfigException`。自定义持久化后端走 SPI：实现 `AgentSessionFactory`（`mode()` 返回已有五种 `MemoryStorageMode` 之一、`create()` 返回 AgentScope Session），在 `META-INF/services/com.yomahub.liteflow.agent.session.factory.AgentSessionFactory` 注册；同 `mode()` 与内置工厂冲突时 **SPI 优先**（典型用途：覆盖 `LOCAL_FILE` 为加密落盘），**不能新增模式名**，`create()` 返回 `null` 表示该模式不持久化。

**会话标识字符合法性**：`conversationId`/`agentKey` 只允许 `[a-zA-Z0-9_-]+`（会拼进 workspace 子目录名和持久化 key）。空值/null → `_`；其他字符先 UTF-8 百分号编码再把 `%` 换成 `_`（如 `chat-用户1` → `chat-_E7_94_A8_E6_88_B71`）。**不要把用户昵称/邮箱原样当 conversationId**（目录名难读），用业务 ID 或哈希。可用 `ExecuteOption.of().autoConversationId()` 让框架首次生成（格式 `YYYYMMDD_<12位NanoId>`）再 `response.getConversationId()` 复用。同一 `(conversationId, agentKey)` 串行（同一把 Session 锁）；`WHEN` 并行 Agent 若 `agentKey` 相同会退化为串行。

**内置文件工具**（`enableWorkspaceFileTools()` 默认 true 时注册）：`read_file`（超 `max-file-bytes` 截断）/ `write_file`（覆盖写、自动建父目录）/ `list_files`（最多 `max-list-size` 条）/ `delete_file`。**全部只接受相对路径**，绝对路径或 `..` 越界报 `path escapes workspace`；文件工具面向文本，要写二进制/大文件应关闭内置工具改自定义工具。

---

## 九、常见坑

- **`workspace.root` 必填**，否则首次执行 Agent 抛 `AgentConfigException: liteflow.agent.workspace.root is required`；生产用绝对路径。
- **`process()` 是 final**，业务逻辑只能通过覆写受保护方法实现，别想覆盖 `process()`。
- **`systemPrompt()` 会被加前缀**——不是最终系统提示词；要固定回复语言须自己显式覆盖。
- **多 Agent 链路必覆写 `handleReply`**：默认 `responseData` 后写覆盖先写。
- **构建期方法（systemPrompt/tools/hooks/skills）只在首次构建缓存生效**，别依赖单次请求数据；按请求隔离改用 `agentKey()` / `resolveConversationId()`。
- **工具/Hook/Model 会被缓存复用**，别在里面保存某次 `ctx()` 引用；运行时通过组件间接 `ctx()`。
- **流式 listener 是同步回调**，只做轻量入队，抛异常会让链路失败。
- **Shell 工具默认就是开启的**：`enableShellTool()` 默认 true 且 `shell.mode` 默认 `WHITELIST`，叠加后用户不配置即开启，默认白名单含 `curl`/`wget`/`python3`/`node` 等强能力命令。注册取逻辑与——组件 `enableShellTool()` 返回 true **且** 配置非 `DISABLED` 才注册，`shell.mode=DISABLED` 是组件无法突破的底线。生产必须显式 `DISABLED` 或收窄白名单。命令按空白切分、`ProcessBuilder` 直执行（不经系统 shell，管道/重定向/变量展开不生效），在 conversation workspace 下执行；工具名 `execute_shell_command`，白名单拦截报 `command not allowed`。
- **运行时异常与重试语义**：模型调用异常（限流/超时/凭据失效）从 `process()` 上抛、体现在 `LiteflowResponse.isSuccess()`/`getCause()`（是 `getCause` 不是 `getException`）。`AgentConfigException` 属配置/构建期问题，应快速失败而非重试；`429` 可退避重试，`5xx`/网络超时可重试或切备用平台 chain，`401/403` 排查凭据。注意同 `conversationId` 重试会沿用上一轮 memory（失败轮可能已写入部分上下文），严格幂等场景用新 `conversationId` 或把 `session.memory.save-on-error` 设为 `false`。
- **JDK 17+**；模型名随厂商更新，以你账号可用模型为准。
