# LiteFlow Agent：会话、历史、事件与 HITL

对齐 LiteFlow 2.16.2／AgentScope 2.0.3。依据 `docs/liteflow-agent-guide.md`、`AbstractAgentComponent`、`AgentConversationService`、`AgentEventTypeMapper` 和存储／守卫实现。完整配置见 [agent-config.md](agent-config.md)。

## 1. 会话身份与续聊

当前身份是 `application-name + conversationId + agentKey`。`application-name` 在 Spring Boot 默认取 `spring.application.name`，`agentKey()` 默认 nodeId，初始化后必须稳定。`requestId` 只标识一次调用，不能替代会话 ID。

当前没有请求级 `userId` 维度，也没有 `resolveUserId(Slot)`／`context.getUserId()`。业务接口自行维护登录用户与 conversationId 的映射，并校验查询、续聊、删除和下载权限。不要用 `customizeRuntimeContext` 设置 AgentScope userId 或替换 sessionId，框架会拒绝这种身份修改。

```java
LiteflowResponse first = flowExecutor.execute2Resp(
        "chatChain", "我叫小明", ExecuteOption.of().autoConversationId());
if (!first.isSuccess()) {
    throw new IllegalStateException("Agent 执行失败", first.getCause());
}
String cid = first.getConversationId();
LiteflowResponse next = flowExecutor.execute2Resp(
        "chatChain", "我叫什么名字？", ExecuteOption.of().conversationId(cid));
```

也可在请求 Map 的 `conversationId` 键中传入，或覆写 `resolveConversationId(Slot)`。未提供时 Agent 按需生成并写回 Slot。`conversationId(...)` 和 `autoConversationId()` 后调用者覆盖前者；已有 ID 必须传回，才能续聊。

应用名、会话 ID、Agent key 都必须是合法单目录名：非空，不能为 `.`／`..`，不能含斜杠、反斜杠、控制字符或 `<>:"|?*`，不能以点或空格结尾。不要依赖自动清洗非法字符。

`runtimeSessionId` 现在等于原 conversationId；`agentNamespace` 由应用名和 agentKey 做长度前缀编码后 SHA-256 得到。物理存储地址由各 Store 包装器负责，业务代码不自行拼接旧哈希路径。

## 2. Session 存储

`session-store` 同时支撑续聊状态、展示历史、工作区和相关快照。默认 JSON；另外两种后端分别引入 `liteflow-agent-redis`／`liteflow-agent-mysql`，版本统一为 2.16.2。没有内置 JVM 内存会话模式。

### JSON

```properties
liteflow.agent.session-store.type=JSON
liteflow.agent.session-store.json-root=/srv/liteflow/state
# 可选；默认 <json-root>/workspace
liteflow.agent.session-store.json-workspace-root=/srv/liteflow/workspace
```

默认根目录 `./data/agent-state` 相对 Java 进程工作目录。单实例可用，部署时保留持久卷；JSON 默认只有 JVM 内调用协调。文件工具默认业务目录为 `<json-workspace-root>/<应用名>/<会话ID>/`。

### Redis

```properties
liteflow.agent.session-store.type=REDIS
liteflow.agent.session-store.redis.uri=${AGENT_REDIS_URI}
# URI 与 Bean 二选一
# liteflow.agent.session-store.redis.client-bean-name=agentRedisClient
# Cluster 需要共同 hash tag，让相关键位于同一 slot
# liteflow.agent.session-store.redis.key-prefix=agent:{prod}:
```

URI 例为 `redis://localhost:6379/0`。Bean 支持 Jedis `UnifiedJedis`、Lettuce `RedisClient`／`RedisClusterClient`、Redisson `RedissonClient`；不要传 `RedisTemplate`。框架也接受其适配器类型，具体以 `RedisAgentStateStoreProvider` 为准。

状态、历史、工作区与 Docker 快照均在 Redis 保存。默认前缀 `agentscope:session:`；没有会话 TTL，服务重启后的保留取决于 Redis 自身持久化。锁租约不是会话过期时间。

### MySQL

```properties
liteflow.agent.session-store.type=MYSQL
liteflow.agent.session-store.mysql.data-source-bean-name=dataSource
liteflow.agent.session-store.mysql.database-name=liteflow_agent
liteflow.agent.session-store.mysql.table-name=agent_sessions
liteflow.agent.session-store.mysql.create-if-not-exist=false
```

或用 `jdbc-url`、`username`、`password` 替代 DataSource Bean。两种连接方式互斥。`database-name` 默认 `agentscope`，不会自动取 JDBC URL 中的库名。默认表名 `agentscope_sessions`，开发时可开启 `create-if-not-exist=true`，账号需建库建表权限。

手工建表时按实际表名替换下面示例，保留版本列与联合主键：

```sql
CREATE TABLE liteflow_agent.agent_sessions (
  session_id VARCHAR(255) NOT NULL,
  state_key VARCHAR(255) NOT NULL,
  item_index INT NOT NULL DEFAULT 0,
  state_data LONGTEXT NOT NULL,
  version BIGINT NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (session_id, state_key, item_index)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE liteflow_agent.agent_sessions_workspace (
  namespace_path VARCHAR(512) NOT NULL,
  item_key VARCHAR(255) NOT NULL,
  value_json LONGTEXT NOT NULL,
  version BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (namespace_path, item_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

先创建数据库。工作区表使用 `table-name` 加 `_workspace`，旧状态表缺 `version` 时先补齐。表名使用字母／下划线开头的 ASCII 字母数字下划线，并给后缀留长度。完整约束与 DDL 以对应 Provider／guide 为准。

### 连接所有权、失败和迁移

- URI／JDBC URL：框架创建并关闭客户端；Bean：应用持有，框架借用。
- `stateStoreResolver()` 可返回 `ResolvedAgentStateStore(store, owned)`；`owned=true` 随 Runtime 关闭，借用共享资源设 false。
- `session-store.failure-policy=LOG_AND_CONTINUE` 只放宽部分延迟加载检查，不能忽略连接、直接加载、保存异常，也不会自动改用另一个后端。
- 修改存储类型不会迁移旧数据。切换前备份并迁移状态、历史、工作区、快照，使用相同应用名、组件 key 和 conversationId 验证重启续聊。
- 同会话的多个 Agent 分别保存模型上下文，共享业务工作区。JSON＋Docker 和共享存储的文件持久化区别见 [agent-harness.md](agent-harness.md)。

## 3. 聊天历史 API

展示历史与模型续聊上下文分开保存；压缩模型上下文不会删掉聊天消息。`conversation-history-enabled=true` 默认启用，关闭不影响模型状态持久化。

Spring 导入服务配置后注入 `AgentConversationService`：

```java
import com.yomahub.liteflow.agent.conversation.AgentConversationConfiguration;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

@Configuration
@Import(AgentConversationConfiguration.class)
public class ConversationConfiguration {}
```

```java
var created = conversations.create("chat-001", "订单咨询", true);
var page = conversations.list(0, 20);
var messages = conversations.messages("chat-001", 0, 50);
var rows = messages.items();
if (messages.hasMore()) {
    var next = conversations.messages("chat-001", messages.nextCursor(), 50);
}
conversations.update("chat-001", "物流进展", java.util.Map.of());
conversations.delete("chat-001");
```

`get(id)` 返回 Optional；`limit` 范围 1～200，cursor 是偏移量。`list` 按最近活动排序。多 Agent 链只想展示用户输入与最终结果时，创建会话用 `recordAgentMessages=false`，由应用调用 `append(...)` 写展示消息，保持全局历史启用以登记关联 Agent。

删除会话会清理展示记录及已登记 Agent 的状态，工作区文件和快照仍需按业务保留策略处理。已删除 ID 不可复用，新会话换新 ID。

非 Spring 可用 `AgentConversationService.open(config)`，退出时关闭服务；构造器 `(config, store)` 借用应用持有的 Store。自定义 Store 需与组件的 resolver 保持一致，不能让查询服务连到另一套存储。

## 4. 事件与 Token 用量

模型 `.stream(true)` 配合 `ExecuteOption.eventListener(...)`：

```java
flowExecutor.execute2Resp("chatChain", "写一首诗",
        ExecuteOption.of().eventListener(event -> {
            if ("agent.text.delta".equals(event.getType())) {
                pushText(event.getText());
            }
        }));
```

`pushText` 是应用提供的 SSE／WebSocket 回调。`execute2Resp` 仍阻塞，`execute2Future` 改变调用方式；任一方式最终检查 response。`agent.result` 只表示当前节点结果，不代表整链成功。

| 事件 | 用途 |
|---|---|
| `agent.start`／`agent.end` | 调用开始／结束 |
| `agent.text.delta`／`agent.thinking.delta` | 正文／思考增量 |
| `agent.tool.call.start`／`.delta`／`.end` | 工具参数流；end 不等于工具执行结束 |
| `agent.tool.result.start`／`.delta`／`.end` | 工具结果阶段，按当前映射支持情况消费 |
| `agent.confirm.required`／`agent.confirm.result` | 审批通知与结果 |
| `agent.result`／`agent.error` | 节点结果／失败 |

`agent.summary` 对应 HintBlockEvent。当前仍兼容发出 `agent.reasoning`／`agent.tool_result`，新消费端优先使用上表事件；不要两套同时追加，避免重复展示。`agent.tool.call.end` 文本为 null，只表示参数已接收完。具体映射以 `AgentEventTypeMapper` 为准。`FlowEvent` 带 chainId、nodeId、requestId、conversationId、timestamp，`AgentFlowEventData` 保留 AgentScope 原事件及 agentKey、traceId 等信息。

监听异常默认 `FAIL_FAST`；容忍展示事件丢失时设置 `event.listener-failure-mode=LOG_AND_CONTINUE`。不能把这种容忍当作可靠消息投递。

覆写 `handleReply(Msg reply, LiteFlowAgentContext context)` 时可从 `context.getChatUsage()` 读取 `getInputTokens()`、`getOutputTokens()`、`getTotalTokens()`、`getCachedTokens()`、`getTime()`。本轮多次模型调用累加，跨会话成本由应用聚合；`getUsedSkills()` 和 `getConfirmationEvents()` 也可在此读取。

## 5. 结构化输出

```java
public record OrderAnswer(String orderId, String status) {}

@Override
protected Class<?> structuredOutputType() {
    return OrderAnswer.class;
}
```

成功时 `response.getSlot().getResponseData()` 为该 Java 类型。动态 schema 使用 `structuredOutputSchema()` 返回 Jackson `JsonNode`，结果也为 JsonNode。两方法不能同时返回非空；解析失败表现为 `AgentInvocationException` 的 `STRUCTURED_OUTPUT` 类型。A2A 组件不支持此接口的结构化模式。

## 6. 人工确认（HITL）

默认权限 BYPASS 不会询问。需要业务审批时设置 ASK 并提供 handler，监听事件本身不能完成审批：

```java
@Override
protected PermissionContextState permissionContext() {
    return PermissionContextState.builder()
            .addAskRule("refund_order", new PermissionRule(
                    "refund_order", null, PermissionBehavior.ASK, "退款需人工确认"))
            .build();
}

@Override
protected AgentConfirmationHandler confirmationHandler() {
    return (event, context) -> awaitApproval(context.getRequestId(), event)
            .map(approved -> event.getToolCalls().stream()
                    .map(tool -> new ConfirmResult(approved, tool)).toList());
}
```

权限类型来自 `io.agentscope.core.permission`，ConfirmResult 来自 `io.agentscope.core.event`，handler 来自 `com.yomahub.liteflow.agent.hitl`。`awaitApproval` 为应用实现、返回 `Mono<Boolean>`，必须等待实际审批回调，不能默认批准。

处理器也可注册唯一 Spring／Solon Bean；组件覆写优先，全局多个候选会报错。每个待确认工具必须恰好对应一条 ConfirmResult，保持工具 ID、名称一致；可在结果中修改已确认的参数。

`hitl.confirmation-timeout` 默认 `2m`，实际等待为该值与 execution-timeout 剩余时间的较小值。默认拒绝后模型继续处理拒绝结果；`fail-on-denied-tool=true` 立即失败。`stopOnReject()` 控制推理停止行为，和使 LiteFlow 节点失败不是同一件事。

等待审批时当前 LiteFlow 调用／Future 未结束，会话锁仍占用。handler 中的 Mono、内存 Future 和调用栈不会由 Store 持久化；进程重启不能从等待点原地恢复。长时审批由业务流程保存审批单、权限和幂等键，完成后用稳定 conversationId 发起新调用。多实例需把回调交给持有该调用的实例或共享消息通道。

## 7. 会话与工作区并发

`invocation-guard.mode=AUTO` 是默认值：JSON 使用 JVM 本地守卫，Redis／MySQL 模块提供分布式协调；显式 LOCAL 只在当前 JVM 生效，BEAN 需提供 `AgentInvocationGuard` 和 bean-name。

`acquire-timeout=2m` 为每次等锁上限。Redis `lease-duration=2m` 是有效锁租约，至少 300ms；框架协调续期／失效，不能将其写成保留字段或聊天 TTL。同一会话的 Harness 工作区另有共享锁，因此不同 nodeId 在同一 conversation 下也可能排队。

`execution-timeout=10m` 从成功取锁和首次 Runtime 构建之后计时，不含上述等待；调用完成或失败后仍可能做额外清理。自定义 guard 需要兑现租约有效性和关闭语义，不能只返回一个永不失效的假锁。

## 8. 排错入口

| 症状 | 检查 |
|---|---|
| 第二轮失忆 | 同一 conversationId、应用名、agentKey 和实际存储 |
| 非法身份 | 单目录名规则；不要传带 `/` 的租户路径 |
| Redis／MySQL 初始化失败 | 模块、连接来源互斥、库表权限、Cluster hash tag |
| 历史正常但文件消失 | 工作区持久化和 Docker 快照是否完整保存 |
| 查询服务看不到历史 | 导入配置、是否和 Agent 使用同一 Store、全局历史开关 |
| ASK 一直等待 | handler 是否返回真实决定，审批是否路由到持有请求的实例 |
| Future 长时间未返回 | 等锁、首次构建、模型、工具、审批和失败清理分别诊断 |
| 删除会话后文件还在 | 删除范围不包含全部工作区和快照；另行清理 |
