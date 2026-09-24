# LiteFlow Agent 配置参考（2.16.2）

根据 `docs/liteflow-agent-guide.md` 第 7 节与 `liteflow-core/src/main/java/com/yomahub/liteflow/property/agent/` 核验。下表均省略 `liteflow.agent.` 前缀，时间使用带单位的 `60s`／`2m`。表中为实际生效默认值，部分存储字段在配置类中为 null，由 Provider 填充。

AgentScope 应在首次调用前完成配置，修改配置对象不会自动重建 Runtime。非 Spring Boot 通过 `LiteflowConfig#setAgent(AgentConfig)` 提供完整配置；应用名不能假定自动回填。Jev 独立使用 `jev.*`，不要求 AgentScope 的应用名、会话、模型或工作区配置，见第 8 节。

## 1. 常用设置

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `application-name` | Spring Boot 中取 `spring.application.name` | 区分应用数据，必须有值并保持稳定 |
| `execution-timeout` | `10m` | 一次 Agent 执行的时限，包含模型、工具和等待审批；不含等锁及首次构建，失败清理可能额外耗时；必须为正 |
| `max-iterations` | `100` | 推理与工具调用的循环上限；必须为正 |
| `execution-log-enabled` | `true` | 是否输出 Agent 执行日志 |
| `conversation-history-enabled` | `true` | 是否自动记录聊天历史；关闭不影响模型续聊状态的保存 |
| `event.listener-failure-mode` | `FAIL_FAST` | 监听器异常时中断；`LOG_AND_CONTINUE` 记录后继续 |

## 2. 存储设置

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `session-store.type` | `JSON` | `JSON`、`REDIS`、`MYSQL` 三选一 |
| `session-store.json-root` | `./data/agent-state` | JSON 状态和历史目录 |
| `session-store.json-workspace-root` | `<json-root>/workspace` | JSON 工作区独立目录 |
| `session-store.failure-policy` | `FAIL_FAST` | 存储加载失败策略；`LOG_AND_CONTINUE` 仅放宽部分延迟加载检查，不会忽略连接、保存等直接异常，也不会自动换后端 |
| `session-store.redis.uri` | 未设置 | Redis URI，与客户端 Bean 二选一 |
| `session-store.redis.client-bean-name` | 未设置 | 已有客户端 Bean 名，与 URI 二选一 |
| `session-store.redis.key-prefix` | `agentscope:session:` | Redis 数据前缀；各实例应一致 |
| `session-store.mysql.jdbc-url` | 未设置 | JDBC 连接，与 DataSource Bean 二选一 |
| `session-store.mysql.username` | 未设置 | JDBC 模式的账号 |
| `session-store.mysql.password` | 未设置 | JDBC 模式的密码 |
| `session-store.mysql.data-source-bean-name` | 未设置 | 已有 DataSource Bean 名 |
| `session-store.mysql.database-name` | `agentscope` | 实际保存数据的数据库，不从 JDBC URL 推断 |
| `session-store.mysql.table-name` | `agentscope_sessions` | 状态与历史表；另有 `_workspace` 后缀表 |
| `session-store.mysql.create-if-not-exist` | `false` | 是否创建库表，开启需对应权限 |

## 3. 执行环境设置

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `harness.filesystem-backend` | `GUARDED_LOCAL` | 本地；可选 `DOCKER`。`CUSTOM` 需实现 `filesystemConfigurer()`，且不能搭配 Redis／MySQL |
| `harness.local.workspace-root` | 未设置 | 本地命令目录；开启本地 Shell 时必填 |
| `harness.shell.mode` | `WHITELIST` | 允许白名单命令；`DISABLED` 与仍开启 Shell 的组件冲突。关闭工具请覆写 `enableShellTool()` |
| `harness.shell.whitelist` | 下方列表 | 自定义值替换默认列表；开启 Shell 时不能为空 |
| `harness.shell.timeout` | `1m` | 单条命令时限；本地至少 `1ms`，Docker 至少 `1s` |
| `harness.docker.image` | `ubuntu:22.04` | 镜像。基础镜像不保证带有所需解释器，应准备业务镜像 |
| `harness.docker.workspace-root` | `/workspace` | 容器内可写的工作目录 |
| `harness.docker.memory-size-bytes` | `536870912` | 内存上限，512 MiB，正整数 |
| `harness.docker.cpu-count` | `1` | CPU 配额，当前只接受正整数 |
| `harness.docker.network` | `NONE` | `NONE`、`BRIDGE`、`HOST`；HOST 行为取决于部署平台 |
| `harness.docker.snapshot-root` | 未设置 | JSON＋Docker 的快照目录；Redis／MySQL 不设置 |
| `harness.docker.lifecycle` | `PER_CALL` | 每次回收；`SESSION_IDLE` 按会话复用 |
| `harness.docker.idle-timeout` | `10m` | 空闲回收时限，必须为正 |
| `harness.docker.eviction-interval` | `30s` | 回收检查间隔，至少 `1ms` |
| `harness.docker.max-cached-sandboxes` | `8` | 每个组件运行时的容器缓存数量，必须为正 |
| `harness.docker.workspace-projection-enabled` | `true` | 是否把静态资料复制到容器 |
| `harness.docker.workspace-projection-roots` | `AGENTS.md,skills,subagents,knowledge,.skills-cache` | 要复制的相对路径；自定义列表替换默认列表，禁止越界路径 |

## 4. Skills、记忆与调用协调

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `skills.enabled` | `false` | 开启配置目录中的技能 |
| `skills.path` | `./skills` | 文件系统目录或 `classpath:` 资源目录 |
| `skills.strict` | `true` | 保留字段，当前不影响运行时行为 |
| `harness.compaction-threshold` | `0.8` | 已知模型容量时的压缩触发比例，取值大于 0、小于 1 |
| `harness.compaction-fallback-context-window` | `524288` | 无法识别容量时使用的 Token 估值，必须为正；自建模型建议显式提供真实容量 |
| `harness.compaction-fallback-threshold` | `0.9` | 使用估值时的触发比例，取值大于 0、小于 1 |
| `harness.memory.flush-mode` | `NEVER` | 逐轮长期记忆提取模式，可选 `ALWAYS`、`THROTTLED` |
| `harness.memory.flush-min-gap` | `5m` | 节流提取的最小间隔，必须为正 |
| `hitl.confirmation-timeout` | `2m` | 等待一轮人工确认的时限，必须为正 |
| `hitl.fail-on-denied-tool` | `false` | 人工拒绝后是否直接使调用失败 |
| `toolkit.parallel` | `false` | 当前组件装配强制串行，设置为 true 不会启用并行 |
| `invocation-guard.mode` | `AUTO` | 按存储选择协调方式；`LOCAL` 仅 JVM 内，`BEAN` 使用自定义实现 |
| `invocation-guard.bean-name` | 未设置 | `BEAN` 模式必填，类型为 `AgentInvocationGuard` |
| `invocation-guard.acquire-timeout` | `2m` | 每次获取会话锁的等待时限，必须为正 |
| `invocation-guard.lease-duration` | `2m` | Redis 锁租约，至少 `300ms`；不控制聊天记录过期 |

## 5. 模型平台和非绑定设置

模型平台 `openai`、`anthropic`、`gemini`、`dashscope` 和兼容平台 Map `openai-compatible.<key>`、`anthropic-compatible.<key>` 都有 `api-key`、`base-url`。内置平台带默认 URL，自定义 compatible 需提供两者；代码显式值优先于文件。`extra.*` 是保留字段，Provider 当前不读取。

采样、流式、Token 上限等通过 ModelSpec 设置，详见 [agent-models-tools.md](agent-models-tools.md)。模型容量缓存目录是 JVM 参数 `liteflow.agent.model-catalog.cache-dir`，不是 Spring Boot 配置绑定字段。

## 6. Shell 默认白名单

```text
sh, bash, python, python3, node, git, npm, npx, java, javac, mvn, gradle,
mkdir, cp, mv, rm, touch, chmod, ls, find, tree, stat, file, basename, dirname, pwd, which,
cat, head, tail, grep, sed, awk, wc, sort, uniq, cut, tr, diff, echo, printf, expr,
date, whoami, hostname, uname, env, df, du, ps, md5sum, sha256sum, jq, curl, wget
```

自定义配置替换整份列表。开启 Shell 的组件不能把 mode 设为 DISABLED，关闭工具使用 `enableShellTool()` 返回 false。命令目录不提供操作系统隔离，完整执行边界见 [agent-harness.md](agent-harness.md)。

## 7. 配置迁移和边界

旧 `runtime.namespace`、`runtime.timeout`、`state-store.*`、`workspace.*`、`harness.trusted-local`、`harness.local-shell-enabled` 不属于当前配置。分别迁移为 application-name、execution-timeout、session-store，以及按需使用 harness.local／harness.docker；完整映射见 [react-agent.md](react-agent.md)。

配置错误应在首次使用前发现：正数时限和次数、0～1 之间且不含端点的比例、连接来源二选一、JSON／共享存储与快照条件、自定义后端限制。不要通过设置不存在的属性绕过校验。

## 8. Jev 智能选择

依据本次新增的 `JevConfig`、`JevProvider` 与 `JevChoiceClient` 核验，日期为 2026-09-21；`jev.noul-threshold` 依据 2026-09-23 的 `2.16.3` 工作区更新核验；`JevProvider.LAYA` 与 `laya` 入口的 `api-key` 放行依据 2026-09-24 的 `2.16.3` 工作区更新核验。以下同样省略 `liteflow.agent.` 前缀。

| 配置 | 默认值 | 用途与约束 |
| --- | --- | --- |
| `jev.provider` | `typesafe` | 仅支持 `typesafe`、`openrouter`、`laya`（`laya` 自 2.16.3 起）；Java 使用 `JevProvider.TYPESAFE`／`OPENROUTER`／`LAYA`，不能为 `null` |
| `jev.api-key` | 未设置 | `typesafe`／`openrouter` 必填，填写所选 provider 的凭据；`laya` 仅当服务端设置 `LAYA_API_KEY` 时填写相同的值，其余情况可留空（客户端不发送 Authorization 头）；非空白时不可包含空格、控制字符或非 ASCII 字符，建议从环境变量注入 |
| `jev.base-url` | 随 provider 选择 | `typesafe`：`https://api.typesafe.ai/v1`，追加 `/systemone`；`openrouter`：`https://openrouter.ai/api/alpha`，追加 `/decisions`；`laya`：`http://127.0.0.1:8000/v1`，追加 `/systemone`。支持末尾斜杠和网关路径，必须为 HTTP(S)，禁止内嵌凭据、query、fragment |
| `jev.model` | 随 provider 选择 | `typesafe`：`jev-1.13.0`；`openrouter`：`typesafe/jev-1.13`；`laya`：`auto`，由其路由器按语言选择 checkpoint，可显式填 `english`／`multilingual`／`typed-decisions` |
| `jev.timeout` | `3s` | 完整 HTTP 响应含响应体的最大等待时间，至少 `1ms` |
| `jev.min-confidence` | `0.6` | 有限数值且在闭区间 `[0, 1]` 内；低于阈值走 `DEFAULT`，可覆写组件 `minConfidence()` |
| `jev.noul-threshold` | `0.5` | 有限数值且在闭区间 `[0, 1]` 内；Noul 概率达到阈值（含）走 true 分支，可覆写组件 `probabilityThreshold()`；2.16.3 起 |

`base-url` 与 `model` 未设置、为 `null` 或为空白时，使用所选 provider 的默认值；显式覆盖值不会随 provider 切换而重置。`base-url` 是 API 根地址，不填完整接口路径。OpenRouter 使用 Decisions API，不使用聊天接口或 `openai-compatible` 配置。`laya` 指向本地自托管的 `laya-serve`（`pip install "laya[serve]"` 后运行），首次加载模型时自动从 Hugging Face 下载 checkpoint。

Spring Boot 在属性绑定时拒绝未知 `provider`，其他运行约束在执行 Jev 组件时校验。`execution-timeout`、`session-store.*`、`harness.*` 等 AgentScope 设置不控制 Jev。完整组件与 EL 示例见 [agent-jev.md](agent-jev.md)。
