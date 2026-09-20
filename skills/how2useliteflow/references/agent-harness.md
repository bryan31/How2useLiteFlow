# LiteFlow Agent：执行环境、压缩与子代理

LiteFlow 2.16.2 的 Harness 已在 `liteflow-agent-core` 内，不再单独引入 `liteflow-agent-harness`。业务入口仍为 `com.yomahub.liteflow.agent.harness.component.HarnessAgentComponent`；纯聊天也用它，最小组件见 [agent.md](agent.md)。依据 agent guide 第 3、6、7 节和 core 下 `harness/` 源码。

## 1. 默认能力与权限

文件工具默认可用：`read_file`、`write_file`、`edit_file`、`list_files`、`grep_files`、`glob_files`。命令工具名为 `execute`，`enableShellTool()` 默认 true；只做聊天、Java／MCP 调用或文件读写时显式返回 false，无需配置命令目录。

未设置非空权限策略时使用 `PermissionMode.BYPASS`，不会自动弹出确认。需要审批时显式配置 ASK 和 handler，见 [agent-state-events-hitl.md](agent-state-events-hitl.md)。BYPASS 不取消文件路径校验、命令白名单或 Docker 资源限制。

## 2. 存储与执行环境选择

| 存储 | GUARDED_LOCAL | DOCKER |
|---|---|---|
| JSON | JSON 保存状态和文件，本地目录运行命令 | JSON 保存状态，快照保存容器业务文件 |
| Redis | Redis 保存状态、历史和文件，本地目录运行命令 | Redis 保存状态和快照 |
| MySQL | MySQL 保存状态、历史和文件，本地目录运行命令 | MySQL 保存状态和快照 |

`session-store.*` 选择持久化位置，`harness.filesystem-backend` 选择命令环境。Java 应用部署在 Docker 内，并不自动意味着 Agent 使用 DOCKER 后端。

### GUARDED_LOCAL

```properties
liteflow.agent.harness.filesystem-backend=GUARDED_LOCAL
liteflow.agent.harness.local.workspace-root=./data/agent-execution
```

只有本地 Shell 开启时要求 `local.workspace-root`。执行目录为 `<root>/<应用名>/<会话ID>/`；运行命令前恢复持久存储中的文件，运行后把变更写回。该目录是执行副本，备份应包括真正的 session-store 工作区。

本地模式现在支持 Shell，不需要旧 `trusted-local` 属性。命令继承 Java 进程权限和环境，工作目录不是操作系统隔离边界；需要隔离进程、网络与资源时选 Docker。后台常驻进程不适合此工具。

### DOCKER

准备 Docker CLI／daemon，并在 Java 服务同一账户下验证 `docker version`、`docker info`。仓库镜像构建入口：

```bash
./liteflow-agent/docker/sandbox/build.sh
```

提供 `liteflow-agent-sandbox:node22`，业务所需解释器与依赖要预装进镜像。默认 `ubuntu:22.04` 不保证包含这些工具。

JSON 配置：

```properties
liteflow.agent.harness.filesystem-backend=DOCKER
liteflow.agent.harness.docker.image=liteflow-agent-sandbox:node22
liteflow.agent.harness.docker.snapshot-root=/srv/liteflow/snapshots
```

Redis／MySQL 使用相同 backend 和 image，但移除 `snapshot-root`，快照由后端保存。本地目录配置也不用于 Docker。JSON 想持久恢复文件应保存快照目录，使用 SESSION_IDLE 时该目录或自定义快照 Provider 必需。

默认容器工作区 `/workspace`，网络 `NONE`，内存 536870912 字节，CPU 为 1；可按需配 `network=BRIDGE`／`HOST`、正整数 `memory-size-bytes` 和 `cpu-count`。这些只控制容器命令，模型 API、Java 工具、MCP 客户端仍在 Java 应用侧运行。

### 容器生命周期

默认 `PER_CALL` 每次调用后保存快照并回收。连续对话可选：

```properties
liteflow.agent.harness.docker.lifecycle=SESSION_IDLE
liteflow.agent.harness.docker.idle-timeout=10m
liteflow.agent.harness.docker.eviction-interval=30s
liteflow.agent.harness.docker.max-cached-sandboxes=8
```

缓存上限按组件 Runtime 计。JSON 的 SESSION_IDLE 快照主要在正常回收时保存，强杀进程可能丢失近期变更；Redis／MySQL 每次调用后保存。快照只覆盖工作区文件，不保存进程、内存和工作区外依赖。

Java 应用本身在容器中时仍需提供 CLI 和 daemon 访问，框架不会自动挂载 Docker socket。当前配置不提供任意 volumes、端口发布或环境变量映射。

### CUSTOM

需覆写 `filesystemConfigurer()` 返回 `HarnessFilesystemConfigurer`，由 `configure(HarnessAgent.Builder, HarnessFilesystemContext)` 安装文件系统。CUSTOM 不能搭配 Redis／MySQL 的托管存储。不要经 `customizeHarness` 偷换内置文件系统；自定义实现负责其隔离、资源关闭与失败清理。

## 3. 命令白名单与超时

```properties
liteflow.agent.harness.shell.mode=WHITELIST
liteflow.agent.harness.shell.whitelist=sh,python3,node,ls,cat,mkdir,pwd
liteflow.agent.harness.shell.timeout=60s
```

自定义列表替换默认白名单。白名单非空且程序实际安装；默认列表含常用解释器、构建和文件工具，完整列表见 [agent-config.md](agent-config.md)。`DISABLED` 与组件仍开启 Shell 冲突，关闭工具应覆写 `enableShellTool()` 返回 false。

`execute` 入参 `command` 必填，`working_directory` 为工作区相对目录，`timeout` 为秒，只能缩短服务端限时。本地服务端限时至少 1ms，Docker 至少 1s。复杂命令写成脚本后执行，避免管道、换行和链式命令被校验器拒绝。

`Unsynchronized files` 表示执行副本可能有未保存数据，先备份报错目录、恢复文件，再处理 pending 标记，不能清空目录掩盖保存失败。

## 4. 输入文件与附件交付

提示词使用 `input/orders.json`、`output/report.md` 等工作区相对路径。JSON 本地业务文件默认在 `<json-root>/workspace/<应用名>/<会话ID>/`，可以独立配置 `json-workspace-root`。

JSON＋Docker 可从 `json-workspace-root` 投影静态资料。默认投影 `AGENTS.md,skills,subagents,knowledge,.skills-cache`，可用 `workspace-projection-enabled` 开关和 `workspace-projection-roots` 替换列表；路径必须相对且不越界。这是复制，不是挂载；容器修改不回写静态源目录。Redis／MySQL 使用 Skills 仓库、文件接口或业务工具提供输入，不把本地目录视为持久存储。

通过 `additionalContextFiles()` 提供固定参考资料的工作区相对路径。需要交付生成文件时，由 `customizeHarness(builder)` 配置应用实现的 `ArtifactDeliveryTarget` 以启用 `deliver_artifact`；应用实现鉴权、附件元数据和下载接口，容器路径本身不是浏览器下载 URL。

## 5. 自动压缩与模型容量

自动压缩默认开启，使用 LiteFlow `AdaptiveCompactionMiddleware`。已知模型窗口时，`harness.compaction-threshold=0.8` 按扣除输出预留后的可用输入预算计算。未知模型使用 `compaction-fallback-context-window=524288` 与 `compaction-fallback-threshold=0.9`。

自建模型优先在 Spec 上配置 `.contextWindow(真实Token上限)`，不能靠放宽阈值解决超窗。模型容量目录缓存默认 `~/.liteflow/model-catalog`，可用 JVM 参数 `-Dliteflow.agent.model-catalog.cache-dir=/srv/liteflow/model-catalog` 修改；不是 Spring Boot 属性。离线显式容量避免依赖目录查询。

`compactionConfig()` 已废弃；非空时仍切回 AgentScope 原生 CompactionConfig 路径，并绕过 LiteFlow 自适应比例中间件。新代码优先使用上述比例配置，不把上游原生阈值当作 LiteFlow 默认。展示历史不因模型上下文压缩被删除。

## 6. 长期记忆与工具结果

普通续聊状态自动持久化，不需要启用逐轮记忆抽取。长期记忆用于稳定事实、偏好，保存到工作区：

```properties
liteflow.agent.harness.memory.flush-mode=THROTTLED
liteflow.agent.harness.memory.flush-min-gap=5m
```

默认 `NEVER` 不每轮额外提取，`ALWAYS` 每轮提取，`THROTTLED` 按间隔提取；会增加模型请求和成本。`HarnessMemoryConfigResolver` 用全局 flush 配置覆盖 `memoryConfig()` 中的 flush trigger，其他模型和提示词配置保留。不要把 AgentScope 上游默认 ALWAYS 当作 LiteFlow 默认。

`toolResultEvictionConfig()` 可设置大型工具结果的落盘阈值和预览，例如 `maxResultChars(80000)`、`previewChars(2000)`。完整结果通过工作区保存，预览不是审计日志。`memoryConfig()` 可指定独立抽取模型；由 Runtime 管理的 Model 不应跨组件共享。

## 7. 子代理、计划和任务

只有 DOCKER／CUSTOM 支持子代理，GUARDED_LOCAL 关闭此能力。与固定 EL 不同，子代理由主模型决定是否调用：

```java
@Override
protected List<SubagentDeclaration> subagents() {
    return List.of(SubagentDeclaration.builder()
            .name("reviewer")
            .description("检查主代理结论中的遗漏和矛盾")
            .inlineAgentsBody("根据已给事实审查，不编造依据。")
            .workspaceMode(WorkspaceMode.ISOLATED)
            .build());
}

@Override
protected boolean enablePlanMode() {
    return true;
}
```

类型来自 `io.agentscope.harness.agent.subagent`。默认继承父模型，迭代上限 10；ISOLATED 独立工作区，SHARED 共享。`inlineAgentsBody`／`workspace` 二选一；`steps`、`tools`、`skills` 可限制迭代和能力，`persistSession(true)` 使用稳定 spawn key 保存续聊。显式 `model(...)` 由 AgentScope ModelRegistry 解析，不自动读取 LiteFlow compatible 平台配置；没有特别需求时继承父模型。

计划需用户批准时，给 `plan_exit` 设置 ASK 并注册确认处理器。子代理的 `inheritParentPermissions(true)` 只继承父 DENY，不等于复制全部 ASK／ALLOW。

远程子代理的 `url(...)`／`headers(...)` 使用 AgentScope task HTTP，和 LiteFlow 的 A2A 客户端不同。远程确认默认 DENY，其他策略须按服务能力选择。

任务默认保存在工作区；`taskRepository()` 可提供自定义实现，`ownsTaskRepository()` 默认 false。`ownedHarnessResources()` 登记由 Runtime 关闭的额外资源。所有 builder 定制必须保留 LiteFlow 托管能力，并返回原 builder。

## 8. 故障定位

| 症状 | 检查 |
|---|---|
| 纯聊天仍报执行目录缺失 | 是否显式关闭默认 Shell |
| 命令拒绝／程序不存在 | 白名单、执行环境和镜像中程序是否齐全 |
| Docker 无法连接 | Java 进程同账户下执行 docker info |
| 容器断网 | 默认 NONE，有需要才改 BRIDGE |
| 重启文件丢失 | 状态与快照是否均持久化，是否只保存了执行副本 |
| 共享存储配本地 snapshot-root 报错 | Redis／MySQL 自带快照，移除冲突配置 |
| 本地子代理不执行 | GUARDED_LOCAL 不提供该能力 |
| 配置压缩比例却没生效 | 是否覆写了非空 compactionConfig，绕过自适应中间件 |
