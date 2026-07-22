# How2useLiteFlow

[English](./README.md) | **中文**

一个帮助 AI 正确使用 **[LiteFlow](https://liteflow.cc)（v2.16.X）** 的 Agent Skill。LiteFlow 是一款轻量级的 Java 规则引擎 / 业务编排框架。本 skill 内置了从官方文档与源码蒸馏出的用法与代码细节（组件、EL 规则、上下文、脚本组件、规则配置源、执行器、AI Agent 编排、测试调试、源码实现等），并规定了"答不到时怎么办"的严格流程——**不杜撰、不拿网络内容充当 LiteFlow 行为依据**。

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

skill 也会自检：每次会话通过 `scripts/version-check.sh` 对比自身 `version` 与远端发布的 SKILL.md，发现新版本时会提示你执行更新命令。结果按天缓存，网络失败时静默跳过，不影响使用。

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

**你只需要安装这个 skill，不需要任何额外配置。** 它能回答**任何** LiteFlow 问题，靠的是一套分层策略：

1. **蒸馏知识（覆盖约 90%）** — 内置高频速查表 + 分主题参考文档（`references/`），全部从 LiteFlow 官方文档与源码蒸馏而来。绝大多数问题——EL 算子、组件类型、执行 API、配置项、源码实现——都直接由这些内容作答，不联网、无需额外设置。
2. **源码托底** — 对于蒸馏知识未覆盖的少数冷门或深层问题，skill 会去读 LiteFlow 的真实源码：优先查找本地 LiteFlow 仓库，没有则在征得你同意后克隆官方仓库，再用精确的 `path:line` 引用作答。
3. **绝不杜撰** — 若 reference 与源码都无法确认，skill 会如实说明，而不是臆测、也不拿网络内容充当 LiteFlow 的行为依据。

也就是说：装上这个 skill，你的 AI 就能可靠地回答 LiteFlow 问题——从日常用法一直到源码级实现。

## 触发方式

当你向 AI 提到 LiteFlow 相关内容（组件、EL 规则、上下文、脚本组件、规则源、执行器、ReAct Agent 编排、测试、源码细节等）时，该 skill 会自动启用。

## 仓库结构

```
skills/how2useliteflow/
├── SKILL.md          # 入口：决策流程 + 高频速查 + 知识地图
├── references/       # 分主题的详细参考文档
├── scripts/          # 本地优先的源码定位、受控克隆与版本自检工具
└── assets/
```
