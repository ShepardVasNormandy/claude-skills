---
name: stack
description: Manage stacked branches and pull requests with the gh-stack GitHub CLI extension (`gh stack`, which must be installed with `gh extension install github/gh-stack`). Use when the user types /stack or /stack status, asks "where is my stack", "show my stack", "submit the stack", "create a branch on the stack", or wants the CI and review status of stacked PRs. Covers worktree-safe branch creation, staging/committing per branch, submitting, navigating, and a script that prints the current stack with PR number, CI and review status into the conversation.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/stack/scripts/stack-status.sh*)
  - Bash
  - Read
  - Edit
  - TodoWrite
---

# Stack

Stacked PRs via the `gh stack` GitHub CLI extension.

Requires: the gh-stack GitHub CLI extension (`gh stack`). If `gh extension list` does not show `github/gh-stack`, tell the user it is missing and how to add it (`gh extension install github/gh-stack`), then stop.

Install once per machine:

```bash
gh extension install github/gh-stack
git config rerere.enabled true           # remember conflict resolutions, skip prompt
git config remote.pushDefault origin     # skip remote picker if >1 remote
```

`gh stack` does not enforce one commit per branch — commit deliberately, but multiple commits per branch are fine.

## Agent rules (non-interactive only)

Every `gh stack` invocation must avoid prompts/TUIs, or it hangs:

- `gh stack view` -> always `--json`
- `gh stack submit` -> always `--auto`
- `gh stack init` / `add` / `checkout` -> always pass branch/PR arguments
- `gh stack checkout <pr>` onto a diverged local stack -> run `gh stack unstack --local` first, then retry
- `gh stack merge` -> always `--yes`

## /stack status

On `/stack` or `/stack status`, run the script and read its output back to the user, calling out what needs action (failing CI, branches needing approval, `(needs rebase)`):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/stack/scripts/stack-status.sh             # current stack
bash ${CLAUDE_PLUGIN_ROOT}/skills/stack/scripts/stack-status.sh --no-fetch  # skip CI/review enrichment
```

It prints the stack top (tip) to bottom (trunk), each branch with its PR number, review status and CI status, and `>` on the current branch. Failing CI jobs are listed with their job ID on indented `↳` lines below the branch, so a job ID can be piped straight into `gh run view --job <id> --log-failed`. Read-only.

## Start a branch

`<default-branch>` below is the repo's default branch, the trunk of the stack. Find it with `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

```
Naming
  Ticket?   yes -> branch name = the ticket's suggested branch name (e.g. Linear's branchName), create it with git checkout -b
            no  -> pick a name that reflects the concern (e.g. auth, api-routes)

Starting point
  First branch of the stack (parent = trunk)
      git checkout -b <name> <default-branch>   # branch from its tip without checking it out
      gh stack init <name>        # adopts the existing branch, no new commits made

  Stacking on an existing branch (tip of the current stack)
      git checkout <tip-of-stack>
      gh stack add <name>         # creates and switches to <name> on top of the stack

Commit and submit
      git add <paths>
      git commit -m "<message>"   # multiple commits per branch are fine
      gh stack submit --auto      # push + create/update PRs (drafts by default)
```

Why these work:
- `git checkout -b <name> <default-branch>` is worktree-safe: it checks out the *new* branch, not the default branch, and git only blocks checking out a branch already live in another worktree.
- `gh stack init` **adopts** an existing branch instead of creating one when it already exists, so it's safe to run right after `git checkout -b`.
- `gh stack add` must be run from the top of the stack (or trunk if the stack is empty) — it errors with exit code 5 otherwise.

## Insert or remove a branch in the middle of a stack

There is no insert command. `gh stack add` only appends to the top, and `gh stack link` rejects a mid-stack argument with *"new PRs must be added to the top of the existing stack"*. Rebuild instead.

**GitHub blocks a base change on a PR that belongs to a stack.** REST answers `422 PullRequest.base is invalid`, GraphQL answers *"Cannot change the base branch because the pull request is part of a stack"*. So `unstack` before anything else, or you create the new PR and then patch bases by hand.

```bash
# 1. commit the new branch off the one it must sit on
git checkout <branch-below>
git checkout -b <new-branch>
git add -A && git commit -m "..."

# 2. drop the GitHub grouping, from a branch already IN the stack (not the new one)
git checkout <branch-below>
gh stack unstack                       # PRs, reviews and approvals all survive

# 3. re-parent each branch above, bottom to top, ONE AT A TIME (see the trap below)
git rebase --onto <new-parent> <own-commit>^ <branch>

# 4. re-declare and re-link
gh stack init <b1> <new> <b2> ...
gh stack push
gh stack submit --auto                 # creates the missing PR, sets every base
```

### The trap: `gh stack rebase` replays the commit you just removed

After you hand-re-parent one branch, `gh stack rebase` duplicates the removed commit into the branch **above** it. Its merge-base with the new parent regresses to the grandparent, so the replayed range still contains that commit. Identical patches drop by patch-id, but a commit absent from the new parent is replayed. It recurs at every level, because each upper branch inherits the same history.

Rebuild bottom to top with an explicit boundary instead. Each branch's own contribution is usually its tip, so:

```bash
git rebase --onto <parent-branch> <that-branch-tip>^ <that-branch>
```

Capture every tip sha **before** starting: each rebase rewrites the shas above it, and a stale sha makes `git rebase --onto` report *"is up to date"* and silently do nothing.

Then verify, do not assume:

```bash
# one commit per branch, and the removed commit gone from the whole chain
git rev-list --count <parent>..<branch>
git log --oneline origin/<default-branch>..<top-branch>
```

## Cheat sheet

| Goal | Command |
|---|---|
| First branch off the default branch (worktree-safe) | `git checkout -b <name> <default-branch>` -> `gh stack init <name>` |
| Stacked branch on the tip | `git checkout <tip>` -> `gh stack add <name>` |
| Append an *existing* committed branch to the stack | `gh stack link <bottom..top PRs/branches> <name>` |
| Commit | `git add <paths>` -> `git commit -m "<msg>"` |
| Submit whole stack (push + open/update PRs) | `gh stack submit --auto` |
| Submit as ready for review (not draft) | `gh stack submit --auto --open` |
| Push without touching PRs | `gh stack push` |
| See the current stack | `gh stack view --json` |
| Move up / down the stack | `gh stack up` / `gh stack down` |
| Jump to top / bottom / trunk | `gh stack top` / `gh stack bottom` / `gh stack trunk` |
| Rebase after a parent changed | `gh stack rebase --upstack` |
| Insert or remove a branch mid-stack | `gh stack unstack` -> re-parent by hand -> `gh stack init` -> `submit --auto` |
| Fetch + rebase + push + sync PR state | `gh stack sync` |
| Merge the whole stack | `gh stack merge --yes` |

## Don'ts

- No `gh stack view` or `gh stack view --short` without `--json` — launches an interactive TUI.
- No `gh pr merge` on a stacked PR — use `gh stack merge --yes`.
- No `git rebase <top-branch>` directly to catch up to trunk — use `gh stack rebase` (or `gh stack sync`).
- No mixing unrelated work into one stack — start a new one with `gh stack init`. A fix that shares no file with the stack belongs on the default branch: inside the stack it waits for every PR below it.
- No `gh stack submit` before `gh stack unstack` when a base has to move — GitHub refuses the base change while the PR is in a stack.
- No `gh stack rebase` to finish a mid-stack re-parent — it replays the commit you removed into the branch above.
