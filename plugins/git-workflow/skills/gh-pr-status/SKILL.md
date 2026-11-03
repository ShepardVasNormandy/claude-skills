---
name: gh-pr-status
description: >
  Formats a "what to check on GitHub" report for the current repo: your own open PRs
  (CI status, review decision, unresolved review-thread count) and PRs where you're a
  reviewer (TO_REVIEW / AUTHOR_REPLIED — PRs already REVIEWED with nothing new are hidden).
  Stacked PRs (base branch is another open PR's head branch) print as an indented tree.
  Use for "/gh-pr-status", "what do I have to check on GitHub", "my PR status",
  "what's awaiting my review", or any request for a GitHub PR status report on this repo.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/gh-pr-status/scripts/gh-pr-status.sh*)
---

# gh-pr-status

Run the bundled script and show its output as-is — it is already formatted (colors,
indentation for stacks, blank lines between unrelated PRs/stacks):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/gh-pr-status/scripts/gh-pr-status.sh          # both sections
bash ${CLAUDE_PLUGIN_ROOT}/skills/gh-pr-status/scripts/gh-pr-status.sh --mine   # only "YOUR OPEN PRs"
bash ${CLAUDE_PLUGIN_ROOT}/skills/gh-pr-status/scripts/gh-pr-status.sh --other  # only "PRs AWAITING YOUR REVIEW"
```

Requires `gh` (authenticated) and `jq`. Operates on the repo in the current working
directory (via `gh repo view`).

Runtime scales with PR count: it makes one GraphQL call per PR to read review threads.
Expect several seconds to run, more with many open/review PRs.

## Shell shortcut

If the user wants a terminal shortcut for this script, do not add an install
subcommand to `gh-pr-status.sh` — the script stays a plain, self-contained reporting
tool. Instead: investigate the current script path yourself, then hand back a
ready-to-paste snippet for the user to add to their `~/.zshrc` themselves.
