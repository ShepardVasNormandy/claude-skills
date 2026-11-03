# team-workflow

A skill for a daily routine: a to-do page of your tickets, mentions and review requests.

## Install

```
claude plugin marketplace add ShepardVasNormandy/claude-skills
claude plugin install team-workflow@claude-skills
```

## Skills

| Skill | What it does |
|---|---|
| `inbox` | Gathers your open tickets (Linear, Jira or GitHub Issues), the Slack messages waiting for your reply and the GitHub PRs awaiting your review into one HTML to-do page. |

## Config

The skill reads `.claude/team-workflow.local.md` in your project and asks for any missing key once. Keys: `tracker`, `slack_user_id`, `github_repos`. See [docs/configuration/team-workflow.md](../../docs/configuration/team-workflow.md). Add `*.local.md` to your `.gitignore` if the values are personal.

## Requirements

- A tracker MCP or `gh`, matching `tracker`: the Linear MCP for Linear, the Atlassian (Jira) MCP for Jira, or the `gh` CLI for GitHub Issues. Needed by `inbox`.
- Slack MCP and `gh`: `inbox` uses them when they are present, and skips them with a note when they are not.
- python3: `inbox`.
