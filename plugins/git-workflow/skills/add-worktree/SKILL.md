---
name: add-worktree
description: "Sets up a second checkout of the repo for a branch, so you can work on it without touching the current working tree. Copies the gitignored files the project needs (dependencies, .env files, local config) from the main worktree and repairs node_modules/.bin links in pnpm repos. Use it to start a new branch in its own folder, to test or review another branch side by side, or through /add-worktree <branch>."
---

# Add Worktree

Creates a git worktree for a branch and copies the gitignored files the project needs from the main worktree (dependencies, `.env` files, generated local config), then, in a pnpm repo, runs a fast frozen `pnpm install` to relink `node_modules/.bin`. The worktree is immediately ready to build, test, and commit, with no manual setup.

## Config

Read `.claude/git-workflow.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `worktree_copy` | Optional, default `node_modules, .env*, .claude/*.local.md`. Gitignored files and directories to copy into a new worktree. A name matches at any depth; a pattern with a `/` matches from the repo root. | `[node_modules, .env*, .claude/*.local.md, certs/*.pem]` |

Optional keys are never asked for: use the default in their meaning.

Suggest setting `worktree_copy` only when the new worktree turns out to miss something (a build cache, a generated config, a local certificate).

## Usage

Run the script from inside the repository (the main checkout or any of its worktrees). When the user runs `/add-worktree <branch>`, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/add-worktree/scripts/add-worktree.sh" <branch>
```

Optionally, a custom path can be provided as second argument:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/add-worktree/scripts/add-worktree.sh" <branch> ~/Projects/my-custom-name
```

If no path is provided, the worktree is created beside the main worktree as `<parent>/<repo>-<branch-last-segment>`. For example, with the main checkout at `~/Projects/orders-service`, branch `jdoe/ord-123-add-refunds` lands in `~/Projects/orders-service-ord-123-add-refunds`. A relative custom path is resolved against the same parent.

## What the script does

1. Finds the default branch (`origin/HEAD`, else what `git ls-remote --symref origin HEAD` reports, else `main`) and fetches it, then checks out the branch as a new git worktree. A branch that is not on the remote is created from `origin/<default-branch>`.
2. Copies from the main worktree every path matching `worktree_copy` that git ignores:
   - a name pattern (`node_modules`, `.env*`) matches at the root and in every subdirectory, so per-package `.env` files come along too. Tests that need local config fail in a fresh worktree without them.
   - a pattern with a wildcard (`.env*`, `.claude/*.local.md`) matches files only, so a `.env/` virtualenv is not copied. A plain name such as `node_modules` also matches a directory, which is copied whole; the script does not look inside `node_modules` for other patterns.
   - tracked files are never copied (they are already in the checkout), nor are `*.example` / `*.example.*` templates, nor anything inside another worktree nested in the main one.
3. If the repo has a `pnpm-lock.yaml` and `node_modules` was copied, runs `pnpm install --frozen-lockfile --prefer-offline` in the worktree to relink `node_modules/.bin`. The `cp -R` copy leaves pnpm's deep symlinks dangling, so binaries such as `turbo` and the pre-commit hooks would otherwise be missing. The lockfile is not changed; the step is non-fatal.
4. Opens the new worktree in VS Code when the `code` command is installed.

## Notes

- If the worktree path already exists, it just opens it and exits.
- The script uses `cp -R` (not symlinks), so each worktree is independent; in pnpm repos the trailing frozen install repairs the `.bin`/`.pnpm` symlink farm that `cp -R` can't preserve.
- If the install step prints a WARNING (e.g. offline store incomplete), run `pnpm install` once in the worktree before running tests or committing.
- The default list copies `.claude/*.local.md`, so the git-workflow config follows the new worktree. Keep that pattern if you set `worktree_copy` yourself.
- Pair it with `/remove-worktree <branch>` once the PR is merged.
