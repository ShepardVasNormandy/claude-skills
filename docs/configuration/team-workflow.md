# team-workflow configuration

Skills in the `team-workflow` plugin read these keys from `.claude/team-workflow.local.md` in the project root (YAML front matter only). A skill asks for a missing key once, writes it to that file, and continues. Keys marked optional are never asked for; the skill uses the default.

| Key | Used by | Meaning | Example |
|---|---|---|---|
| `slack_user_id` | inbox | Optional, default: resolved from the Slack MCP and saved. If it cannot be resolved, the skill skips the Slack source and says why. Your Slack member id. | `UXXXXXXXXX` |
| `github_repos` | inbox | Optional, default: every repo you can see. Repos to read. | `[acme/web-app, acme/orders-service]` |
| `tracker` | inbox | Required. Where tickets live: `linear` (Linear MCP), `jira` (Atlassian/Jira MCP) or `github-issues` (the `gh` CLI). The skill lists your assigned open items through that tracker. | `linear` |

Optional keys are never asked for: use the default in their meaning.

## MCP servers

| Skill | Needs |
|---|---|
| inbox | The tracker's tool (Linear MCP, Atlassian/Jira MCP or `gh`, per `tracker`); Slack MCP and `gh` optional |

## Example

```markdown
---
slack_user_id: UXXXXXXXXX
github_repos: [acme/web-app, acme/orders-service]
tracker: jira
---
```
