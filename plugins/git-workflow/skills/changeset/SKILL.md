---
name: changeset
description: Writes Changesets entries for a JavaScript or TypeScript monorepo. Detects the workspaces from pnpm-workspace.yaml or the package.json workspaces field, finds the packages changed on the branch, skips the ones ignored in .changeset/config.json, picks patch, minor or major for each, and writes a one-line user-facing summary. Use when the user types /changeset, asks to "add a changeset", "write the changesets" or "bump the packages", or before committing a change to a published package in a repo with a .changeset folder.
---

# Changeset

Write one changeset entry per changed package, with the right bump and a summary a user of the package can read.

## 1. Check the repo uses Changesets

The repo needs a `.changeset/` folder with a `config.json`. If it has none, tell the user and stop. Do not set Changesets up unless they ask.

## 2. Find the workspaces

- `pnpm-workspace.yaml`: read the `packages` globs.
- Otherwise, the `workspaces` field of the root `package.json` (an array, or an object with a `packages` array).
- Neither: the repo is a single package. Use the root `package.json`.

Expand the globs to folders that contain a `package.json`, and read each package's `name` and `private` fields.

## 3. Find the changed packages

```bash
base=$(git merge-base HEAD origin/$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name))
git diff --name-only "$base"...HEAD
git diff --name-only HEAD
```

Map each file to the package whose folder contains it. Then drop:
- packages listed in `ignore` in `.changeset/config.json` (entries can be globs);
- private packages, unless `privatePackages.version` is `true` in the config;
- packages whose only changes are tests, stories or docs that are not shipped;
- packages that already have a changeset on this branch for the same change.

If nothing is left, say so and stop.

## 4. Pick the bump

| Change | Bump |
|---|---|
| Bug fix, internal refactor, dependency update, performance work | patch |
| New feature, new option or export, new behaviour that old callers do not notice | minor |
| Removed or renamed export, changed signature, changed default, dropped runtime support | major |

For a package still on `0.x`, a breaking change is a minor bump. When a change could be read two ways, ask the user.

## 5. Write the summary

One line per package, written for the people who use the package. Start with a verb, describe what changed for them, and leave out file names and internals.

| Package | Bump | Summary |
|---|---|---|
| `@acme/storefront` | minor | Show estimated delivery date on the order page |
| `@acme/catalog` | patch | Update date-fns to 4.1.0 |
| `@acme/checkout` | patch | Keep the coupon when the cart is reloaded |
| `@acme/ui` | major | Remove the deprecated `size="xl"` prop from Button |

Packages that changed for the same reason can share one changeset file.

## 6. Write the file

Write the file directly. It is the most reliable way to stay non-interactive:

```markdown
---
"@acme/storefront": minor
"@acme/catalog": patch
---

Show estimated delivery date on the order page
```

Save it as `.changeset/<short-kebab-name>.md`, for example `.changeset/order-page-delivery-date.md`.

If the user prefers the CLI, `pnpm changeset add --empty` (or `npx changeset add --empty`) creates an empty file without prompts. Fill in the front matter and summary afterwards. Never run `changeset` or `changeset add` without `--empty`, because both open prompts.

## 7. Report

List each file written, with its packages, bumps and summary. If the user is about to commit, the `commit` skill reuses the summary as the commit message.
