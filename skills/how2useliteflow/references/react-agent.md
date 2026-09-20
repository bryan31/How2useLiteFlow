# 迁移到 LiteFlow Agent 2.16.2

先识别用户实际依赖和源码版本。2.16.2 发布准备期间经历过多轮 API 调整，不能只比较版本字符串。以下目标以 2026-09-19 源码和当前 agent guide 为准。

## 1. 依赖与组件迁移

| 旧用法 | 当前替代 |
|---|---|
| `liteflow-react-agent-*` | 对应 `liteflow-agent-*` 模块，统一版本 2.16.2 |
| 迭代版独立 `liteflow-agent-harness` | `liteflow-agent-core` |
| `ReActAgentComponent`／中间态 `AgentComponent` | `com.yomahub.liteflow.agent.harness.component.HarnessAgentComponent` |
| `userPrompt()` | `userPrompt(LiteFlowAgentContext context)` |
| `handleReply(reply)` | `handleReply(reply, context)` |
| `ctx()`／`ReActAgentContext` | 方法参数 `LiteFlowAgentContext` |
| `hooks()` | `middlewares()` 返回 AgentScope `MiddlewareBase` |
| `customizeAgent(...)` | `customizeHarness(HarnessAgent.Builder)`，修改并返回原 builder |
| `skills()` 名称列表 | `skillFilter()` 返回 `SkillFilter` |
| `usedSkills()` | `context.getUsedSkills()` |
| `enableWorkspaceFileTools()` | 文件工具默认提供；命令开关为 `enableShellTool()` |
| `resolveUserId(...)`／上下文 getUserId | 已移除，业务实现用户与会话归属校验 |

AgentScope 由 LiteFlow BOM 管理为 2.0.3，Agent 需要 JDK 17+。模块合并不改变 HarnessAgentComponent 包名。完整新组件和依赖使用 [agent.md](agent.md)，不能混入旧 ReAct Builder。

## 2. 配置迁移

以下均省略 `liteflow.agent.` 前缀。旧属性不保证有别名兼容，必须实际修改：

| 旧属性／机制 | 当前属性／处理 |
|---|---|
| `runtime.namespace` | `application-name`；Spring Boot 可沿用 spring.application.name |
| `runtime.timeout` | `execution-timeout`，默认 10m |
| `state-store.*`／`session.memory.*` | `session-store.*`；JSON／Redis／MySQL |
| JVM／LOCAL_FILE memory 模式 | JSON 持久化，默认 ./data/agent-state |
| `workspace.root` | 存储选 session-store.json-workspace-root；本地命令选 harness.local.workspace-root |
| `workspace.trusted-local`／`harness.trusted-local` | 移除；本地命令使用进程权限，需要隔离选 Docker |
| `shell.*` | `harness.shell.*`，默认 WHITELIST |
| `harness.local-shell-enabled` | 组件 enableShellTool() |
| `defaults.max-iterations` | `max-iterations`，默认 100 |
| `logging.react-enabled` | `execution-log-enabled` |
| 自己用 Redis／MySQL 共享状态却只有本地锁 | invocation-guard.mode=AUTO 默认选择分布式协调 |

纯聊天要显式关闭默认开启的 Shell。JSON＋Docker 持久恢复文件需保留 snapshot-root；Redis／MySQL 由存储保存快照，移除该本地路径。`skills.strict` 和 `toolkit.parallel` 当前不产生对应运行效果，不要写成迁移开关。

## 3. 会话和文件迁移

当前身份为 application-name、conversationId、稳定 agentKey。不要按请求改变 agentKey，也不要依赖旧 userId 哈希布局。应用名和 ID 必须是合法单目录名，旧含路径字符的值先显式映射。

旧会话、文件、快照不会自动搬迁，修改 session-store.type 只切换后端。升级前备份，先用新会话验证运行，再按目标 Store 协议迁移需要保留的数据并验证重启恢复。查询展示历史使用 AgentConversationService，删除不会自动清掉全部工作区文件和快照。

多个 Agent 在同一会话共享工作区并受锁协调；EL WHEN 不保证同时运行。并行结果分别写业务 Context 或 Slot.output，最后一个节点汇总 responseData。

## 4. 权限、事件与扩展

默认权限 BYPASS；以前依赖默认 ASK 的代码必须显式返回 ASK 规则并注册 AgentConfirmationHandler。只有监听确认事件不能继续执行。等待审批的调用不会持久化成可跨进程恢复的工作流。

新页面消费 agent.text.delta、agent.tool.call.*、agent.tool.result.*、agent.result 和 agent.error。源码仍兼容发出 agent.reasoning／agent.tool_result；不要新旧两套同时追加。模型必须 stream(true)，事件回调接 SSE／WebSocket；agent.result 不等于整链成功。

`compactionConfig()` 已废弃但非空仍切换到上游原生配置路径，新代码使用 harness.compaction-threshold 和 ModelSpec.contextWindow。逐轮长期记忆提取默认 NEVER，需要时配置 flush-mode；不要沿用上游 ALWAYS 的默认值假设。

## 5. 升级验证

至少验证：一次完整调用、同 ID 续聊、应用重启恢复、response.getCause() 错误分支，以及实际使用的文件／命令／Skills／MCP／HITL 入口。多 Agent 验证结果不互相覆盖；共享存储验证跨实例会话协调；删除验证展示记录、Agent 状态与文件保留范围。

源码离线例子见 agent.md 和 testing.md；默认值／属性绑定测试见 AgentGuideDefaultsTest、AgentPropertyBindingTest。真实模型与 Docker 集成验证按项目环境运行，不能把离线模型测试当作平台连通性证明。
