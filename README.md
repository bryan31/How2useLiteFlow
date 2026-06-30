# How2useLiteFlow

一个帮助 AI 正确使用 **[LiteFlow](https://liteflow.cc)（v2.16.X）** 的 Agent Skill。内置了从官方文档与源码蒸馏出的用法与代码细节（组件、EL 规则、上下文、脚本组件、规则配置源、执行器、AI Agent 编排、测试调试、源码实现等），并规定了"答不到时怎么办"的严格流程——**不杜撰、不拿网络内容充当 LiteFlow 行为依据**。

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

## 触发方式

当你向 AI 提到 LiteFlow 相关内容（组件、EL 规则、上下文、脚本组件、规则源、执行器、ReAct Agent 编排、测试、源码细节等）时，该 skill 会自动启用。

## 仓库结构

```
skills/how2useliteflow/
├── SKILL.md          # 入口：决策流程 + 高频速查 + 知识地图
├── references/       # 分主题的详细参考文档
├── scripts/          # source-lookup.sh：本地优先 / 受控克隆 + 源码检索
└── assets/
```

## 许可

参见仓库 LICENSE（如有）。LiteFlow 为 [dromara/liteFlow](https://gitee.com/dromara/liteFlow) 项目。
