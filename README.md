# How2useLiteFlow

**English** | [中文](./README.zh-CN.md)

An Agent Skill that helps AI use **[LiteFlow](https://liteflow.cc) (v2.16.1)** correctly — a lightweight Java rule engine / business orchestration framework. It bundles usage and source-level details distilled from the official docs and source code, including the seven Rule-DB backends (SQL, PostgreSQL, MongoDB, Redis, ZooKeeper, etcd, and Nacos), metrics, components, EL rules, scripts, execution, AI Agent orchestration, testing, and internals. It also enforces a strict "what to do when the answer isn't covered" workflow — **never fabricate, never pass web content off as LiteFlow's actual behavior**.

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

## Update

Installed skills are static copies — new releases are not pushed automatically. To update:

```bash
npx skills update how2useliteflow -g -y   # global install
npx skills update how2useliteflow -p -y   # project install
```

The skill also checks itself: once per session it compares its own `version` against the published `SKILL.md` via `scripts/version-check.sh`, and offers to run the update command when a newer release exists. Results are cached once per day, and network failures are skipped silently.

### Optional: enforce the check with an agent hook

The self-check above is an instruction the agent *should* follow, not a guarantee. To make it mandatory, wire the script into your agent's hook system (skills cannot modify your agent config for you). Adjust the script path to where the skill was installed, and keep the trailing `|| true` — some hook systems read exit code 2 as "block", which here means "update available".

**Kimi Code CLI** (`~/.kimi-code/config.toml`) — runs when your prompt mentions LiteFlow; stdout is appended to context:

```toml
[[hooks]]
event = "UserPromptSubmit"
matcher = "[Ll]ite[Ff]low"
command = "sh ~/.agents/skills/how2useliteflow/scripts/version-check.sh || true"
```

**Claude Code** (`~/.claude/settings.json`) — runs at every session start; stdout is added to context:

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
├── scripts/          # Local-first source lookup, controlled clone helper, and version self-check
└── assets/
```
