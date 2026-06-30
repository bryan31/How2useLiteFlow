# How2useLiteFlow

**English** | [中文](./README.zh-CN.md)

An Agent Skill that helps AI use **[LiteFlow](https://liteflow.cc) (v2.16.X)** correctly — a lightweight Java rule engine / business orchestration framework. It bundles usage and source-level details distilled from the official docs and source code (components, EL rules, context, script components, rule sources, executor, AI Agent orchestration, testing & debugging, internals), and enforces a strict "what to do when the answer isn't covered" workflow — **never fabricate, never pass web content off as LiteFlow's actual behavior**.

## Install

One-line install via the [`skills` CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add bryan31/How2useLiteFlow
```

Optional flags:

```bash
# global (user-level) install, target a specific agent, skip confirmation
npx skills add bryan31/How2useLiteFlow@how2useliteflow -g -a claude-code -y
```

The entire skill directory (including `references/` and `scripts/`) is copied into your agent's config directory — no extra setup needed.

## How it triggers

The skill activates automatically when you mention anything LiteFlow-related (components, EL rules, context, script components, rule sources, executor, ReAct Agent orchestration, testing, source internals, etc.).

## Repository layout

```
skills/how2useliteflow/
├── SKILL.md          # entry: decision workflow + quick-reference + knowledge map
├── references/       # detailed reference docs by topic
├── scripts/          # source-lookup.sh: local-first / controlled clone + source search
└── assets/
```
