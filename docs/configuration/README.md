# Configuration

Skills that need project-specific values (a ticket format, a tracker project, a Notion database, an app URL) read them from one file per plugin in the project where you use them:

| Plugin | Config file | Keys |
|---|---|---|
| git-workflow | `.claude/git-workflow.local.md` | [git-workflow.md](git-workflow.md) |
| agent-discipline | `.claude/agent-discipline.local.md` | [agent-discipline.md](agent-discipline.md) |
| review-and-design | `.claude/review-and-design.local.md` | [review-and-design.md](review-and-design.md) |
| team-workflow | `.claude/team-workflow.local.md` | [team-workflow.md](team-workflow.md) |

You don't have to write these files by hand. The first time a skill needs a value that isn't there, it asks you once and saves the answer. Add `*.local.md` to your `.gitignore` if the values are personal.

Each file is YAML front matter only:

```markdown
---
ticket_pattern: "[A-Z]+-[0-9]+"
ticket_in: trailer
---
```

## Writing a skill that uses config

Paste this block into the skill and fill in the table. `tests/config-contract.sh` checks the block is there and that every key is listed in the plugin's key file.

```markdown
## Config

Read `.claude/<plugin>.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
```

Mark a key as optional in its Meaning column ("Optional, default …") and add this line under the table. Optional keys are never asked for.

```markdown
Optional keys are never asked for: use the default in their meaning.
```

## Writing a skill that needs an MCP server

Add one line per server. The contract test checks the line ends the skill when the server is missing.

```markdown
Requires: <server> MCP. If its tools are not available, tell the user which server is missing and how to add it (`claude mcp add …` or the plugin that ships it), then stop.
```

## Script portability

Skill scripts run on macOS (bash 3.2, BSD tools) and Linux. `scripts/validate.sh` rejects `date -d`/`--date`, `mapfile`, `readarray` and `${var,,}`/`${var^^}` anywhere in a script, including inside a fallback branch. For date arithmetic, call `node -e` or `python3 -c` instead.
