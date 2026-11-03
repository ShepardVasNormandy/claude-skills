---
name: remove-worktree
description: "Cleans up a git worktree after its branch has been merged. Runs git worktree remove, deletes the local branch and prunes remote refs. It stops without changing anything when the worktree has uncommitted changes, unpushed commits or a PR that is not merged. Use it when a feature branch is finished and its extra checkout can go, through /remove-worktree <branch>, or when asked to tidy up old worktrees."
---

# Remove Worktree

Safely tears down a git worktree created by `/add-worktree`. It removes the worktree with `git worktree remove` (so git's metadata stays consistent — never `rm -rf`), deletes the now-merged local branch, and prunes stale remote-tracking refs.

The script finds the main worktree from the current directory, so run it from anywhere inside the repository (the main checkout or any of its worktrees).

## Usage

When the user runs `/remove-worktree <branch>`, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/remove-worktree/scripts/remove-worktree.sh" <branch>
```

### Picking a worktree (when no exact branch is given)

If the user runs `/remove-worktree` with no argument, or with a partial/ambiguous name, **first list the existing worktrees** and let them choose — don't guess:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/remove-worktree/scripts/remove-worktree.sh" --list
```

This prints every worktree of the repository except the main one. Present them to the user, then re-run with the chosen branch. (The script also auto-lists when called with no branch.)

Optionally, a custom worktree path can be provided as the second argument (mirrors `add-worktree`):

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/remove-worktree/scripts/remove-worktree.sh" <branch> ~/Projects/my-custom-name
```

Path resolution mirrors `add-worktree`:
- If no path is given, the worktree is assumed beside the main worktree at `<parent>/<repo>-<branch-last-segment>` (e.g. `~/Projects/orders-service-ord-123-add-refunds` for branch `jdoe/ord-123-add-refunds`).
- A relative custom path is resolved against the parent of the main worktree.

## Safety model

The script **blocks and exits with code 2** (without removing anything) if any of these is true:

1. The worktree has uncommitted or untracked changes
2. **The local commits are not proven merged.** They are proven merged when the branch tip is an ancestor of `origin/<default-branch>`, or when `gh pr view <branch> --json state,headRefOid` reports `MERGED` and the tip is an ancestor of that `headRefOid` (this covers squash merges). If the PR is merged but the tip has commits that are not in the merged PR head, it blocks with "commits after the merged PR; use --force to discard". If the PR is not merged, it blocks with "not merged".
3. The branch has unpushed commits, or was never pushed. A branch whose upstream is `origin/<default-branch>` (what `/add-worktree` sets up before the first push) counts as never pushed: its commits are unpushed work.

Once check 2 proves every commit merged, check 3 is downgraded to a note: commits ahead of a stale remote branch are in the merged PR.

### When it blocks because the PR is not merged

Do **not** silently force. Show the user the blocker reasons the script printed, then **ask whether they're sure they want to remove the worktree anyway**. Only if they confirm, re-run with `--force`:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/remove-worktree/scripts/remove-worktree.sh" <branch> [worktree-path] --force
```

`--force` (recognized in any position) overrides all three checks at once (it uses `git worktree remove --force` and `git branch -D`). The same applies if the block is due to a dirty worktree, unpushed commits or commits after the merged PR — surface it, confirm, then force. Forcing discards those commits.

## What the script does (happy path)

1. Computes the worktree path from `<branch>` (or the 2nd-arg override), the same way `add-worktree` does
2. Verifies it's a registered worktree and refuses to remove the main worktree
3. Runs the three safety checks above
4. `git worktree remove <path>`
5. `git branch -d <branch>` (keeps it if not fully merged and not forced)
6. `git fetch --prune` to drop stale remote-tracking refs

## Notes

- Path handling is symmetric with `/add-worktree`, so a worktree added with one is removed with the other using the identical branch argument.
- Typical flow: `/add-worktree <branch>` → work, push, open PR → PR merged → `/remove-worktree <branch>`.
