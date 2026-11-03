---
name: commit
description: Commits the current work with a Conventional Commits message (`type(scope): summary`), with the scope taken from the changed workspace packages and the ticket placed according to project config. Uses the changeset summary as the message when the repo uses Changesets, and works on a gh-stack branch when the repo uses stacked PRs, otherwise on a plain branch. Decides between amending and a new commit. Use when the user types /commit, or asks to "commit this", "commit my changes", "write the commit message" or "amend the commit".
---

# Commit

Commit the work in the working tree with a clear message, on the right branch.

## Config

Read `.claude/git-workflow.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `ticket_in` | Where the ticket reference goes: `trailer`, `branch` or `none` | `trailer` |
| `ticket_pattern` | Optional, default `[A-Z]+-[0-9]+`. Regex of a ticket key | `[A-Z]+-[0-9]+` |

Optional keys are never asked for: use the default in their meaning.

## 1. Look at the change

```bash
git status --short
git diff --stat
git diff --cached --stat
```

If nothing is staged, stage the files that belong to the task the user just finished. Leave unrelated files alone and mention them at the end. If the change covers two unrelated concerns, ask whether to split it before you commit.

## 2. Pick the branch

Check whether the repo uses gh-stack: `gh extension list` shows `github/gh-stack` and `gh stack view --json` succeeds on the current branch.

Requires (stack path only): the gh-stack GitHub CLI extension. If the repo uses stacked branches and `gh stack` is not installed, tell the user to run `gh extension install github/gh-stack`, then stop.

| Situation | Action |
|---|---|
| On the default branch, no stack | `git checkout -b <name>` with a name that reflects the change, or the ticket's branch name |
| On the default branch, repo uses stacks | `git checkout -b <name>` then `gh stack init <name>` |
| On a stack branch, the change belongs to it | Stay on it |
| On a stack branch, the change is a new concern | Go to the top of the stack, then `gh stack add <name>` |
| On a feature branch, no stack | Stay on it |

Follow the `stack` skill for every `gh stack` command. Never run one that opens a prompt.

## 3. Write the message

Format:

```
type(scope): imperative summary

Optional body: why the change was made, in plain sentences.

Refs: ORD-123
```

**Type.** `feat` for new behaviour, `fix` for a bug, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, or `chore` for upkeep such as dependency bumps.

**Scope.** Take it from the changed workspace packages. Read the `name` field of the `package.json` nearest to each changed file and drop the npm scope (`@acme/storefront` becomes `storefront`).
- One package changed: use its name.
- Two or three packages: join them with commas, for example `feat(storefront,checkout): ...`.
- More than three, or a change only at the repo root: leave the scope out.
- Not a monorepo: use the top-level folder of the change, or leave the scope out.

**Summary.** Imperative mood, lower case after the colon, no full stop, at most 72 characters for the whole first line.

**Changesets.** If the repo has a `.changeset/` folder and this change added a changeset file, reuse its summary as the commit summary, rewritten in the imperative if needed. If the change touches a published package and has no changeset, run the `changeset` skill first.

**Ticket.** Find the ticket key with `ticket_pattern` in the branch name, then in the user's request.
- `trailer`: add `Refs: <ticket>` as the last line, after a blank line. With no ticket found, ask once. If the user has none, leave the trailer out.
- `branch`: the ticket lives in the branch name only. Do not repeat it in the message.
- `none`: no ticket anywhere.

Examples:

```
feat(storefront): let customers save a delivery note

Refs: ORD-482
```

```
fix(checkout): keep the coupon when the cart is reloaded
```

```
chore(catalog,search): update date-fns to 4.1.0
```

## 4. New commit or amend

| Situation | Action |
|---|---|
| Repo uses stacks and the branch already holds its one commit, which this work continues | `git commit --amend`, keep the subject unless the scope of the branch changed |
| Repo uses stacks and the branch has no commit of its own yet | New commit |
| The last commit is already pushed and other people may have pulled it, outside a stack | New commit |
| Plain branch, the work is a separate step | New commit |
| The user asked to amend | Amend |

Count a branch's own commits with `git rev-list --count <parent>..HEAD`, where the parent is the branch below it in the stack or the default branch.

Pass the message with a heredoc so the trailer survives:

```bash
git commit -F - <<'EOF'
feat(storefront): let customers save a delivery note

Refs: ORD-482
EOF
```

## 5. After the commit

Show `git log --oneline -1` and the branch name. On a stack, offer `gh stack submit --auto`. Do not push unless the user asks.
