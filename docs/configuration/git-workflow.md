# git-workflow configuration

Skills in the `git-workflow` plugin read these keys from `.claude/git-workflow.local.md` in the project root (YAML front matter only). A skill asks for a missing required key once, writes it to that file, and continues. Optional keys are never asked for: the skill uses the default.

| Key | Used by | Meaning | Example |
|---|---|---|---|
| `ticket_in` | commit, fix-osv | Where the ticket reference goes: `trailer` (a `Refs: <ticket>` trailer line at the end of the commit message), `branch` (only in the branch name), or `none` (no tickets) | `trailer` |
| `ticket_pattern` | commit, fix-osv | Optional, default `[A-Z]+-[0-9]+`. Regex of a ticket key. Not used when `ticket_in` is `none` | `[A-Z]+-[0-9]+` |
| `linear_team` | fix-osv (ticket step) | Key of the Linear team that owns vulnerability tickets. Only asked for when the ticket step runs, and not needed when `ticket_in` is `none` | `ORD` |
| `security_project` | fix-osv (ticket step) | Optional, default `none`. Linear project for vulnerability tickets, or `none` | `Dependency Security` |
| `security_label` | fix-osv (ticket step) | Optional, default `none`. Linear label for vulnerability tickets, or `none` | `security` |
| `test_workflow` | flaky-tests (`unit`) | Workflow file whose runs execute the unit tests | `ci.yml` |
| `test_job` | flaky-tests (`unit`) | Name of the test job as it appears in a run (`<caller job> / <called job>` for a reusable workflow) | `checks / unit-tests` |
| `e2e_workflow` | flaky-tests (`e2e`) | Workflow file that runs the E2E tests | `e2e.yml` |
| `e2e_job` | flaky-tests (`e2e`) | Optional, default: every job of the run. Name of the E2E job to read, when the workflow has other jobs | `playwright` |
| `worktree_copy` | add-worktree | Optional, default `node_modules, .env*, .claude/*.local.md`. Gitignored files and directories copied into a new worktree. A name matches at any depth; a pattern with a `/` matches from the repo root. A pattern with a wildcard matches files only, so a `.env/` virtualenv is not copied by `.env*` | `[node_modules, .env*, .claude/*.local.md, certs/*.pem]` |

The scripts accept lists in either YAML form:

```markdown
---
ticket_in: trailer
ticket_pattern: "[A-Z]+-[0-9]+"
test_workflow: ci.yml
test_job: "checks / unit-tests"
worktree_copy:
  - node_modules
  - ".env*"
  - ".claude/*.local.md"
---
```

The flaky-tests scripts also take each key from the upper-case env var of the same name (`TEST_WORKFLOW`, `TEST_JOB`, `E2E_WORKFLOW`, `E2E_JOB`), which wins over the file. Scripts read the file from the main worktree, so a run inside another worktree uses the same values.
