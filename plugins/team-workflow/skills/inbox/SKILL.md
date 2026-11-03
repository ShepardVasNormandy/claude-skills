---
name: inbox
description: "Builds a personal to-do page for the day. Gathers the open tickets assigned to you in Linear, Jira or GitHub Issues, the Slack messages waiting for your reply and the GitHub PRs where your review is requested, then opens them as one HTML page. Nothing is saved in the project. Use it when asked what is on your plate, what needs your attention, or to start the day through /inbox."
allowed-tools:
  - ToolSearch
  - Bash
  - Write
  - Read
---

# Inbox

One-shot action-item pull. Writes `inbox.html` to a temp folder and opens it — nothing persisted in the project.

## Config

Read `.claude/team-workflow.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `tracker` | Where tickets live: `linear`, `jira` or `github-issues`. | `linear` |
| `slack_user_id` | Optional, default: resolved from the Slack MCP (the search tool description or your own profile) and saved to the config file. If it cannot be resolved, the skill skips the Slack source and says why in the footer. Your Slack member id. | `UXXXXXXXXX` |
| `github_repos` | Optional, default: every repo you can see. Repos to search for PRs and issues. | `[acme/web-app, acme/orders-service]` |

Optional keys are never asked for: use the default in their meaning.

Requires: Linear MCP when `tracker` is `linear`. If its tools are not available, tell the user which server is missing and how to add it (`claude mcp add …` or the plugin that ships it), then stop.

Requires: Atlassian (Jira) MCP when `tracker` is `jira`. If its tools are not available, tell the user which server is missing and how to add it (`claude mcp add …` or the plugin that ships it), then stop.

Requires: the GitHub CLI (`gh`) when `tracker` is `github-issues`. If `gh auth status` fails, tell the user to install `gh` and run `gh auth login`, then stop.

Slack and GitHub PRs are optional. When Slack or `gh` is not connected, skip its steps and say so in the footer.

## Tracker operations

This skill needs one operation from the tracker, "List my assigned items", open items only:

| Tracker | How |
|---|---|
| Linear MCP | `get_user("me")`; `list_issue_statuses` for each relevant team to collect terminal state ids (type `completed`, `canceled` or `duplicate`); `list_issues` with `assignee: "me"`, `includeArchived: false`, limit 50. Keep only issues whose `state.id` (or `stateId`) is **not** terminal. If the state field is absent or null, exclude the issue, never assume it is open |
| Atlassian (Jira) MCP | `searchJiraIssuesUsingJql` with `assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, duedate ASC`, 50 results. Atlassian MCP calls need the `cloudId` from `getAccessibleAtlassianResources`. |
| GitHub Issues (`gh`) | `gh search issues --assignee=@me --state=open --json number,url,title,updatedAt,labels,repository --limit 50`, with one `--repo` per repo in `github_repos` when it is set |

## Step 1 — Detect sources (parallel)

| Source | Check |
|--------|-------|
| Tracker | Linear: `ToolSearch("select:mcp__Linear__list_issues")`. Jira: `ToolSearch("jira search issues jql")`. GitHub Issues: `gh auth status 2>&1` |
| Slack  | `ToolSearch("select:mcp__plugin_slack_slack__slack_search_public_and_private")` |
| GitHub | `gh auth status 2>&1` — available if exit 0 |

Tool names vary with how the server was installed. If a `select:` finds nothing, search by keyword (`ToolSearch("linear list issues")`, `ToolSearch("jira search")`, `ToolSearch("slack search")`) before you call the source unavailable.

Skip an unavailable Slack or GitHub source and note it in the footer only, for example "Slack not connected, skipped".

## Step 2 — Ask scope (once, before fetching)

```
Which scope?
• Tracker: all assigned to me / specific team or project? (default: all open)
• GitHub: all repos / specific ones? (default: github_repos, else all)
• Slack: which channels? how far back? (default: all, last 48h)
Say "everything" for defaults.
```

Skip if user already specified scope.

## Step 3 — Fetch in parallel

**Tracker** — "List my assigned items" from the table above, in parallel with the other sources. Map each item to the `tracker` shape below: `priority` from the tracker's priority field, `statusType` from the state type (Linear), the status category (Jira: To Do → `unstarted`, In Progress → `started`) or `started` for an open GitHub issue, and `group` from the due date and priority (`overdue`, `soon`, `priority`, else `backlog`).

**GitHub PRs** — `gh search prs --review-requested=@me --state=open --json url,title,author,updatedAt,repository --limit 30`
**GitHub Issues** — `gh search issues --assignee=@me --state=open --json url,title,updatedAt,labels,repository --limit 30`. Skip this call when `tracker` is `github-issues`: those issues already go in the tracker section.
Add one `--repo owner/name` per repo when the user named repos or `github_repos` is set.

**Slack** — skip when Slack is not connected. `slack_search_public_and_private` query: `<@SLACK_USER_ID> after:YYYY-MM-DD`, with `slack_user_id` from config. When it could not be resolved, skip Slack and say why in the footer. Filter to messages with action signals (?, "can you", "please", "waiting on", "thoughts?", "need your", "review"). Exclude messages *from* the user.

## Step 4 — Write & open HTML

Locate the template. It sits next to this file; if you do not know this skill's folder, search the plugin cache:
```bash
find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" -path "*/inbox/template.html" 2>/dev/null | head -1
```

Write the data (shape below) as JSON to `${TMPDIR:-/tmp}/inbox-data.json` with the Write tool, then inject it into the template and open the page (`open` on macOS, `xdg-open` on Linux):
```bash
out="${TMPDIR:-/tmp}/inbox.html"
python3 -c "
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
with open(sys.argv[2]) as f: t = f.read()
print(t.replace('__INBOX_DATA__', json.dumps(data).replace('</', '<' + chr(92) + '/')))
" "${TMPDIR:-/tmp}/inbox-data.json" TEMPLATE_PATH > "$out" && { open "$out" 2>/dev/null || xdg-open "$out"; }
```

Output only a one-line summary to the conversation (e.g. "Opened: 12 Jira · 3 GitHub · 5 Slack").

### Data shape

```json
{
  "date": "YYYY-MM-DD",
  "time": "HH:MM",
  "sources": {
    "tracker": { "available": true,  "count": 0, "error": null, "name": "Linear|Jira|GitHub Issues", "url": "https://linear.app" },
    "github":  { "available": true,  "count": 0, "error": null },
    "slack":   { "available": false, "count": 0, "error": null }
  },
  "tracker": [
    { "id": "ORD-123", "title": "...", "url": "...", "priority": "urgent|high|medium|low|none", "group": "overdue|soon|priority|backlog", "status": "In Progress", "statusType": "triage|backlog|unstarted|started|completed|canceled", "due": "Jun 9" }
  ],
  "github_prs": [
    { "number": 42, "title": "...", "url": "...", "repo": "owner/name", "author": "...", "ago": "2h ago" }
  ],
  "github_issues": [
    { "number": 99, "title": "...", "url": "...", "repo": "owner/name", "ago": "1d ago" }
  ],
  "slack": [
    { "quote": "...", "url": "...", "channel": "#name", "author": "Alice", "ago": "3h ago", "urgency": "high|medium|low" }
  ]
}
```

`statusType` is the state type of the item; the template colours the status badge from it, so custom state names still render. For a GitHub issue, `id` is `web-app#42`. `sources.tracker.url` is the tracker's home (the Linear workspace, the Jira site, or `https://github.com/issues/assigned`).

On source error: set `"error": "message"` in the sources object; the template renders a warning banner.
