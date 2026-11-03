# git-workflow

Skills for the daily git and GitHub routine: worktrees, stacked PRs, commits, changesets, dependency vulnerabilities and flaky tests.

## Install

```
claude plugin marketplace add ShepardVasNormandy/claude-skills
claude plugin install git-workflow@claude-skills
```

## Skills

| Skill | What it does |
|---|---|
| `add-worktree` | Sets up a branch in its own folder beside the main checkout and copies over the gitignored files the project needs. Relinks `node_modules/.bin` in pnpm repos. |
| `remove-worktree` | Cleans up a worktree, its local branch and stale remote refs once the PR is merged, using `git worktree remove`. Stops if the worktree has uncommitted changes, unpushed commits or an unmerged PR. |
| `stack` | Manages stacked branches and PRs with `gh stack`: creating branches, committing per branch, submitting and navigating. A script prints the stack with PR number, CI and review status. |
| `gh-pr-status` | Reports your open PRs with CI status, review decision and unresolved thread count, and the PRs waiting for your review. Stacked PRs print as a tree. |
| `commit` | Commits the current work with a Conventional Commits message, scoped to the changed packages, with an optional ticket trailer. Uses `gh stack` when the repo works with stacked branches, otherwise a plain branch. |
| `changeset` | Writes Changesets entries for the changed packages of a JavaScript or TypeScript monorepo: bump type from a short decision table and a one-line user-facing summary each. |
| `fix-osv` | Gets a failing OSV scan passing: picks a fix for each advisory (direct bump, parent bump, override or recorded risk), applies it with pnpm, npm or yarn, reruns the scan and opens a PR. With the Linear MCP it can also file a ticket. |
| `flaky-tests` | `unit` mode ranks tests by failure rate over the last N CI runs and flags those failing on several branches. `e2e` mode writes a Markdown report from the failure annotations of recent E2E runs. |

## Config

The skills read `.claude/git-workflow.local.md` in your project and ask for any missing key once. Keys: `ticket_in`, `ticket_pattern`, `linear_team`, `security_project`, `security_label`, `test_workflow`, `test_job`, `e2e_workflow`, `e2e_job`, `worktree_copy`. See [docs/configuration/git-workflow.md](../../docs/configuration/git-workflow.md). Add `*.local.md` to your `.gitignore` if the values are personal.

## Requirements

- `gh` CLI, authenticated: `gh-pr-status`, `flaky-tests`, `stack`, `fix-osv`, `changeset`. `jq` as well for `gh-pr-status`, `flaky-tests` and `stack`.
- gh-stack extension (`gh extension install github/gh-stack`): `stack`; `commit` and `fix-osv` when the repo uses stacked branches.
- osv-scanner: `fix-osv`.
- Linear MCP: the ticket step of `fix-osv`. Without it the skill reports the missing MCP, skips the ticket step and continues with the rest.
- node or python3: `flaky-tests` uses one of them for date arithmetic.
