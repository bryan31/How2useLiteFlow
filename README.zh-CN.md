# How2useLiteFlow

[English](./README.md) | **中文**

一个帮助 AI 正确使用 **[LiteFlow](https://liteflow.cc)（v2.16.2）** 的 Agent Skill。LiteFlow 是一款轻量级的 Java 规则引擎／业务编排框架。本 skill 内置了从官方文档与源码蒸馏出的用法与代码细节，包括 Rule-DB 的 SQL、PostgreSQL、MongoDB、Redis、ZooKeeper、etcd、Nacos 七后端，以及指标监控、组件、EL 规则、脚本、执行器、AgentScope 2 集成、Jev 智能选择、测试调试和源码实现；并规定了“答不到时怎么办”的严格流程——**不杜撰、不拿网络内容充当 LiteFlow 行为依据**。

> **知识基线（2026-09-19）：**LiteFlow `2.16.2`、AgentScope Java `2.0.3`。AgentScope 入口为 `liteflow-agent-core` 中的 `HarnessAgentComponent`。示例统一使用 `2.16.2`；镜像未同步时核对仓库，或先安装匹配源码。
>
> **Jev 增量（2026-09-21）：**新增 [Jev 智能选择](skills/how2useliteflow/references/agent-jev.md)，覆盖 `liteflow-agent-jev`、`JevSwitchComponent`、`typesafe`／`openrouter` 两种 provider、默认地址与模型、配置覆盖规则、置信度、`DEFAULT`、异常和离线测试。要求 JDK 17+，独立于 AgentScope；依据本次 `2.16.2` 源码更新，使用前确认源码或制品已包含该模块。

## 安装

通过 [`skills` CLI](https://github.com/vercel-labs/skills) 一键安装：

```bash
npx skills add bryan31/How2useLiteFlow
```

可选参数：

```bash
# 全局安装（用户级）、指定 agent、跳过确认
npx skills add bryan31/How2useLiteFlow@how2useliteflow -g -a claude-code -y
```

安装后整个 skill 目录（含 `references/`、`scripts/`）会被拷贝到你的 agent 配置目录，无需额外配置。

## 更新

安装后的 skill 是静态副本，新版本不会自动推送。手动更新：

```bash
npx skills update how2useliteflow -g -y   # 全局安装
npx skills update how2useliteflow -p -y   # 项目安装
```

skill 也会自检：每次会话通过 `scripts/version-check.sh` 对比自身 `version` 与远端发布的 SKILL.md，发现新版本时会提示你执行更新命令。结果按天缓存；网络或解析失败时会输出简短诊断，但不影响正常使用。

### 可选：用 agent hook 强制执行检查

上面的自检是「agent 应当遵守的指令」，不是硬保证。如需强制，可以把脚本挂进 agent 的 hook 体系（skill 无法替你修改 agent 配置）。注意把脚本路径改成实际安装位置，并保留末尾的 `|| true`——部分 hook 体系把退出码 2 解释为「阻断」，而这里它的含义是「有更新」。

**Kimi Code CLI**（`~/.kimi-code/config.toml`）——当你的提问提到 LiteFlow 时运行，输出会追加进上下文：

```toml
[[hooks]]
event = "UserPromptSubmit"
matcher = "[Ll]ite[Ff]low"
command = "sh ~/.agents/skills/how2useliteflow/scripts/version-check.sh || true"
```

**Claude Code**（`~/.claude/settings.json`）——每次会话启动时运行，输出会加入上下文：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh ~/.claude/skills/how2useliteflow/scripts/version-check.sh || true"
          }
        ]
      }
    ]
  }
}
```

## 工作原理

**安装后即可使用分主题参考资料与本地源码查询。** 覆盖率按当前 guide 章节和核心文档页面的明确清单计算，详见[覆盖报告](skills/how2useliteflow/references/coverage.md)。这是文档功能覆盖率，不是 Java 测试覆盖率，也不代表问答准确率。

1. **蒸馏知识** — 内置高频速查表与分主题参考文档（`references/`），全部从 LiteFlow 2.16.2 文档与源码蒸馏而来。EL 算子、组件类型、执行 API、配置项、AgentScope 2、Rule-DB、常见排错和源码实现等问题可直接作答，不联网、无需额外设置。
2. **源码托底** — 对于蒸馏知识未覆盖的少数冷门或深层问题，skill 会去读 LiteFlow 的真实源码：优先查找本地 LiteFlow 仓库，没有则在征得你同意后克隆官方仓库，再用精确的 `path:line` 引用作答。
3. **绝不杜撰** — 若 reference 与源码都无法确认，skill 会如实说明，而不是臆测、也不拿网络内容充当 LiteFlow 的行为依据。

也就是说：装上这个 skill，你的 AI 就能可靠地回答 LiteFlow 问题——从日常用法一直到源码级实现。

## 触发方式

当你向 AI 提到 LiteFlow 相关内容（组件、EL 规则、上下文、脚本组件、规则源、执行器、AgentScope 2 编排、测试、源码细节等）时，该 skill 会自动启用。

## 仓库结构

```
skills/how2useliteflow/
├── SKILL.md          # 入口：决策流程 + 高频速查 + 知识地图
├── references/       # 分主题的详细参考文档
└── scripts/          # 本地优先的源码定位、受控克隆与版本自检工具
```
