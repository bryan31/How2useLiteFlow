# How2useLiteFlow

**English** | [中文](./README.zh-CN.md)

An Agent Skill that helps AI use **[LiteFlow](https://liteflow.cc) (v2.16.2)** correctly — a lightweight Java rule engine / business orchestration framework. It bundles usage and source-level details distilled from the official docs and source code, including the seven Rule-DB backends (SQL, PostgreSQL, MongoDB, Redis, ZooKeeper, etcd, and Nacos), metrics, components, EL rules, scripts, execution, AgentScope 2 integration, Jev intelligent routing, testing, and internals. It also enforces a strict "what to do when the answer isn't covered" workflow — **never fabricate, never pass web content off as LiteFlow's actual behavior**.

> **Baseline (2026-09-19):** LiteFlow `2.16.2`, AgentScope Java `2.0.3`. The AgentScope entry point is `HarnessAgentComponent` from `liteflow-agent-core`. Examples use `2.16.2`; if your Maven mirror has not synchronized it, verify the repository or install matching source locally.
>
> **Jev addition (2026-09-21):** [Jev intelligent routing](skills/how2useliteflow/references/agent-jev.md) covers the new `liteflow-agent-jev` module and `JevSwitchComponent`, including the `typesafe` and `openrouter` providers, their default endpoints and models, configuration overrides, confidence thresholds, `DEFAULT`, errors, and offline tests. It requires JDK 17+ and works independently of AgentScope. This addition follows the current `2.16.2` source update; confirm the module is present in your source or artifacts before use.

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

The skill also checks itself: once per session it compares its own `version` against the published `SKILL.md` via `scripts/version-check.sh`, and offers to run the update command when a newer release exists. Results are cached once per day. Network or parse failures print a short diagnostic and never block normal use.

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

**Install the skill to use its topic references and local-source fallback.** Coverage is measured against an explicit inventory of current guide sections and core documentation pages; see the [coverage report](skills/how2useliteflow/references/coverage.md). This is documentation feature coverage, not Java test coverage or measured answer accuracy.

1. **Distilled knowledge** — a built-in quick-reference plus topic-by-topic reference docs (`references/`), distilled from LiteFlow's 2.16.2 documentation and source code. Most questions — EL operators, component types, execution APIs, configuration, AgentScope 2, Rule-DB, troubleshooting, and internals — are answered directly, with no network access and no extra setup.
2. **Source-code fallback** — for the rare deep or obscure question the distilled knowledge doesn't cover, the skill reads the actual LiteFlow source: it first looks for a local LiteFlow repo, and otherwise (with your consent) clones the official repo, then answers with exact `path:line` citations.
3. **Never fabricate** — if something can't be confirmed from the references or the source, the skill says so plainly instead of guessing or passing web content off as LiteFlow's behavior.

Net effect: install the skill, and your AI can reliably answer LiteFlow questions — from everyday usage all the way down to source-level internals.

## How it triggers

The skill activates automatically when you mention anything LiteFlow-related (components, EL rules, context, script components, rule sources, executor, AgentScope 2 orchestration, testing, source internals, etc.).

## Repository layout

```
skills/how2useliteflow/
├── SKILL.md          # entry: decision workflow + quick-reference + knowledge map
├── references/       # detailed reference docs by topic
└── scripts/          # Local-first source lookup, controlled clone helper, and version self-check
```
