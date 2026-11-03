# agent-discipline

Skills that keep an agent on task, precise and economical: a scope guard, controlled English, model routing, skill authoring and skill updates.

## Install

```
claude plugin marketplace add ShepardVasNormandy/claude-skills
claude plugin install agent-discipline@claude-skills
```

## Skills

| Skill | What it does |
|---|---|
| `no-side-quests` | Holds a task to its stated scope. Unrelated problems it spots, such as a flaky test or an outdated dependency, are listed at the end and left untouched until you decide. |
| `asd-ste100` | Rewrites text in Simplified Technical English. Use it for tool descriptions, error messages and instructions to other agents, where a misreading has a cost. |
| `model-router` | Splits a request into independent tasks, picks a model and effort for each, and runs one sub-agent per task in parallel. It stays active for the rest of the thread. |
| `skill-creator` | Drafts a new skill with its scripts and references, or reviews an existing one for weak triggers, bloat and unclear steps. Works on marketplace, repo and personal skills, and ships a validator script. |
| `update-project-skills` | Brings an installed marketplace up to date and lists the skills that were added, changed or removed, with a reminder to restart Claude Code. |

## Config

This plugin has no config keys. See [docs/configuration/agent-discipline.md](../../docs/configuration/agent-discipline.md).

## Requirements

No MCP servers. Some skills use a local tool:

- node 18+: `model-router`.
- python3: the validator of `skill-creator`.
- `claude` CLI: `update-project-skills`.
- Optional: set `TYPESAFE_API_KEY` to have `model-router` route with Jev. Without it the skill routes by its own rules.

`skill-creator` is based on Anthropic's skill-creator and is under Apache-2.0. See [LICENSE.txt](skills/skill-creator/LICENSE.txt).
