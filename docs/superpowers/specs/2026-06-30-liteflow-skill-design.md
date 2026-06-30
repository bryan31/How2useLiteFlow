# 设计文档：`liteflow-skill`

- 日期：2026-06-30
- 目标产物：一个符合 Anthropic Skill 规范的、可渐进式加载的 Claude Skill，帮助用户用 AI 使用 LiteFlow（Java 规则/编排引擎，对齐 v2.16.X）。
- 落地位置：`/Users/bryan31/openSource/How2useLiteFlow/liteflow-skill/`（独立 skill 目录，便于后续复制到 `~/.claude/skills/` 或打包分发）。

## 1. 背景与目标

LiteFlow 是一个轻量级规则引擎/业务编排框架，通过 DSL（EL 表达式）驱动工作流，支持热重载与 11 种脚本语言、多种规则配置源、声明式组件等。文档量大（v2.16.X 共 122 篇 md），源码模块多。用户希望：

1. 让 AI 在被问到 LiteFlow 时，能基于**内置的、经过蒸馏的**用法与代码细节直接作答；
2. 对内置知识未覆盖的问题，**绝不杜撰、绝不引用网络内容**，而是先征得用户同意后 `git clone` 官方仓库、从源码中找答案；
3. 产物符合 Anthropic Skill 规范，支持渐进式加载（SKILL.md 为入口，深度内容按需加载）。

## 2. 已确认的关键决策

| 决策项 | 选择 |
|---|---|
| 打包形式 | 独立 skill 目录（`liteflow-skill/`），位于工作目录下 |
| 内容语言 | 中文（SKILL.md 的 `description` 保留英文关键词以保证触发） |
| Fallback 模式 | 本地优先：先查内置 reference → 再查本地源码 → 仍不足时征得用户同意后 `git clone`（gitee，固定 `v2.16.0`）读取源码 |
| 覆盖范围 | 全面：16 个文档章节全部蒸馏为 reference + 1 个 code-internals + 1 个 faq-pitfalls |

## 3. 组织方式：分层速查（方案 C）

- `SKILL.md` 内置**高频速查表**（EL 算子、组件类型、执行 API、核心配置项），使约 80% 的常见提问无需加载任何 reference 即可作答。
- 深度问题按**知识地图**打开对应 `references/*.md`。
- 源码级问题走 fallback 协议（本地源码 / 受控克隆）。

## 4. 目录结构

```
liteflow-skill/
├── SKILL.md                 # 入口：触发条件 + 高频速查 + 知识地图 + fallback 决策流程 + 引用规范 + 约束
├── references/
│   ├── overview.md          # 定位/执行模型/模块地图/版本与JDK支持
│   ├── quickstart.md        # SpringBoot·Spring·Solon 安装运行 / Hello World
│   ├── config.md            # 配置项全集（SpringBoot/Spring/Solon/代码）+ LiteflowConfig 关键项
│   ├── components.md        # 继承式(普通/选择/布尔/次数循环/迭代) + 声明式(类级/方法级) + 生命周期钩子 + 方法覆盖
│   ├── el-rules.md          # EL 全语法 + 组件参数语法(tag/data/bind) + 重试/超时/继承/验证/注释/分号/包装
│   ├── context.md           # 上下文定义/初始化传入/别名/参数注入/表达式取参
│   ├── executor.md          # 执行方法/流程入参/LiteflowResponse/直接执行EL
│   ├── scripts.md           # 11种脚本语言/与Java交互/混合/文件脚本/动态刷新/验证/卸载
│   ├── rule-sources.md      # 本地/SQL/ZK/Nacos/Etcd/Apollo/Redis(轮询+订阅)/自定义
│   ├── metadata.md          # 元数据操作器/平滑热刷新/启动不检查规则/脚本
│   ├── thread-pools.md      # FlowExecutor层/组件异步层/虚拟线程
│   ├── dynamic-build.md     # 构造Node/EL/Chain
│   ├── decision-routing.md  # 决策路由概念+用法
│   ├── lifecycle.md         # 启动时/执行时生命周期
│   ├── advanced.md          # 文件监听/降级/别名/回调/回滚/隐式子流程/保活/私有投递/切面/步骤信息/异常/打印/请求Id/快速解析/多格式加载/自定义执行器/监控/DTD
│   ├── code-internals.md    # FlowExecutor/FlowBus/DataBus/Slot/Condition树/两阶段解析/组件继承图/算子→类映射（均带 path:line）
│   └── faq-pitfalls.md      # 常见坑 + FAQ
├── scripts/
│   └── source-lookup.sh     # 本地优先 / 受控克隆+搜索（仅在用户确认后由 Claude 调用）
└── assets/                  # 预留
```

## 5. `SKILL.md` 骨架

- **frontmatter**：`name: liteflow`；`description` 覆盖 LiteFlow 用法/源码/调试类提问，中英文均触发，声明对齐 v2.16.X 与"未覆盖时克隆源码作答、不杜撰"。
- **何时使用**：列举触发场景（写组件、EL 规则、上下文、脚本、规则源、配置、调试链路、源码实现……）。
- **高频速查**：EL 算子速查表、组件类型速查表、执行 API、核心配置项。
- **知识地图**：问题类型 → reference 文件名的映射表。
- **回答决策流程（严格遵守）**：内置 reference → 本地源码 → 征得同意后克隆 → 否则明示"无法确认，不臆测"。
- **引用规范**：usage 题标注 reference 文件名；code 题标注源码 `path:line`。
- **绝对禁止**：未读源码/文档凭记忆编造 API；用网络搜索结果作为 LiteFlow 行为依据。

## 6. Fallback 协议（核心）

回答任何 LiteFlow 问题时的决策流程：

1. **内置优先**：在 `references/` 中查找。覆盖 → 直接作答，标注来源 reference 文件。
2. **本地源码**：未覆盖时，按顺序探测本地仓库（环境变量 `LITEFLOW_REPO` → `~/openSource/liteFlow` → `./liteFlow`）。命中 → 用 `grep`/Read 搜索，引用 `path:line` 作答。
3. **受控克隆**：本地也没有，或问题明确需要线上/最新源码时，**必须先告知用户并请求确认**：
   > "这部分内容不在我的内置知识里。我需要 git clone LiteFlow 仓库（gitee.com/dromara/liteFlow，固定到 v2.16.0）到临时目录读取源码来确认。是否允许？"
   - 用户确认 → 运行 `scripts/source-lookup.sh`（或手动 `git clone` + `grep`）→ 引用源码作答。
   - 用户拒绝/未确认 → 明确告知"无法确认，不建议臆测"，**绝不杜撰、绝不引用网络内容**。

**绝对禁止**：在未读源码/文档的情况下凭记忆编造 API、参数、行为；用网络搜索结果作为 LiteFlow 行为依据（除非用户明确要求联网查证）。

## 7. `scripts/source-lookup.sh` 设计

- 子命令：
  - `ensure`：本地优先——若 `LITEFLOW_REPO` 或默认本地路径存在则直接复用；否则 `git clone --depth 1 --branch v2.16.0 https://gitee.com/dromara/liteFlow.git <cache>`。打印解析出的仓库绝对路径。
  - `grep <pattern>`：在仓库 `**/*.java` 中检索，输出 `path:line: 内容`。
  - `find <name>`：按文件名查找。
  - `show <path> [start-end]`：显示某文件（可选行号区间）。
- 环境变量：`LITEFLOW_REPO`（本地仓库覆盖）、`LITEFLOW_TAG`（默认 `v2.16.0`）、缓存目录默认 `$HOME/.cache/liteflow-skill`。
- 兼容性：优先 `rg`，缺失时回落 `grep -rn`；纯 POSIX sh 兼容，不依赖 bash 特性。
- **职责边界**：脚本只做机械的"确保仓库 + 检索/展示"，**不做用户交互**。是否允许克隆由 Claude 依据 SKILL.md 协议先行征得用户同意。

## 8. 内容来源与准确性保证

- **usage 类 reference**（quickstart / components / el-rules / context / executor / scripts / rule-sources / metadata / thread-pools / dynamic-build / decision-routing / lifecycle / advanced / config / overview）：从 `liteflow-homepage/docs/04.v2.16.X文档` 的 122 篇 md 蒸馏。每个 reference 顶部注明其来源文档清单；正文不臆造。
- **code-internals.md**：从 `liteFlow` 源码提炼（配合 `.codegraph` 索引），所有结论附 `path:line`，必要时附关键代码片段。
- **faq-pitfalls.md**：综合文档中的注意点与常见易错用法。
- **作者方式**：用并行 subagent 按专题读取文档/源码产出草稿 → 统一审校一致性、补 `path:line`、贯穿"不杜撰"纪律。不使用 workflow（用户未启用）。

## 9. 验证标准（DoD）

- 目录结构完整，`SKILL.md` frontmatter 合法（`name` kebab-case ≤64 字符；`description` 简洁且含触发关键词）。
- 每个 reference 文件可独立读懂，顶部标注来源文档/源码。
- SKILL.md 决策流程与 fallback 协议清晰可执行；脚本 `source-lookup.sh` 在 macOS（zsh/sh）下可运行。
- 抽测：对若干典型问题（如"如何写一个选择组件""WHEN 的超时怎么配""DataBus 的 slot 机制"），能从 skill 内正确作答并标注来源；对一个冷门问题，能正确触发"请求克隆"流程而非杜撰。

## 10. 非目标 / 范围外

- 不打包成 plugin / marketplace（本期为独立 skill 目录）。
- 不把全部 122 篇文档逐字搬入；以"蒸馏要点 + 来源标注"为准。
- 不内置任何网络检索能力；联网仅作为用户显式同意下的受控克隆手段。
- 工作目录非 git 仓库，设计文档暂不纳入版本控制（如需可后续 `git init`）。
