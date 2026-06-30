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

## How it works

**Just install this skill — nothing else to configure.** It can answer **any** LiteFlow question through a layered strategy:

1. **Distilled knowledge (covers ~90%)** — a built-in quick-reference plus topic-by-topic reference docs (`references/`), distilled from LiteFlow's official documentation and source code. The vast majority of questions — EL operators, component types, the execution API, config keys, internals — are answered directly from these, with no network access and no extra setup.
2. **Source-code fallback** — for the rare deep or obscure question the distilled knowledge doesn't cover, the skill reads the actual LiteFlow source: it first looks for a local LiteFlow repo, and otherwise (with your consent) clones the official repo, then answers with exact `path:line` citations.
3. **Never fabricate** — if something can't be confirmed from the references or the source, the skill says so plainly instead of guessing or passing web content off as LiteFlow's behavior.

Net effect: install the skill, and your AI can reliably answer LiteFlow questions — from everyday usage all the way down to source-level internals.

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
