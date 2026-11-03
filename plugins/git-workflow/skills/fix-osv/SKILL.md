---
name: fix-osv
description: "Gets a red OSV scan green. Locates the failing CI job, lists the advisories behind it and chooses a fix for each: bump the dependency, bump its parent, add an override, or record an accepted risk with a reason and an expiry. Applies the change with pnpm, npm or yarn, reruns osv-scanner as CI does, then commits and opens a PR. It can also file a Linear ticket. Use it through /fix-osv, when a vulnerability check blocks a merge, or when given a CVE or GHSA id to patch."
---

# Fix OSV

Turn a red OSV scan green with the smallest dependency change that removes each advisory.

Requires: osv-scanner (`osv-scanner --version`). If it is missing, tell the user how to install it (`brew install osv-scanner` or `go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest`), then stop.

## Config

Read `.claude/git-workflow.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `ticket_in` | Where the ticket reference goes: `trailer`, `branch` or `none` | `trailer` |
| `ticket_pattern` | Optional, default `[A-Z]+-[0-9]+`. Regex of a ticket key | `[A-Z]+-[0-9]+` |
| `linear_team` | Linear team for vulnerability tickets. Ask only when the ticket step runs | `ORD` |
| `security_project` | Optional, default `none`. Linear project for vulnerability tickets | `Dependency Security` |
| `security_label` | Optional, default `none`. Linear label for vulnerability tickets | `security` |

Optional keys are never asked for: use the default in their meaning.

## 1. Find the failing job

```bash
gh run list --branch "$(git branch --show-current)" --limit 10 --json databaseId,workflowName,conclusion,headSha
gh run view <run-id> --json jobs -q '.jobs[] | select(.conclusion=="failure") | {name, databaseId}'
gh run view --job <job-id> --log-failed
```

If the user gave a PR or run link, start from it. Find the workflow file that runs the scan (`grep -rl osv-scanner .github/workflows`) and note the exact command, flags and config file it uses (`osv-scanner.toml`, `--lockfile`, `--recursive`, `--config`).

## 2. List the failing advisories

From the log, or by running the CI command locally with `--format json`, build one row per advisory:

| Advisory | Package | Installed | Fixed in | Path from a direct dependency |
|---|---|---|---|---|
| `GHSA-xxxx-xxxx-xxxx` | `follow-redirects` | 1.15.4 | 1.15.6 | `@acme/http-client` > `axios` > `follow-redirects` |

Get the path with `pnpm why <pkg>`, `npm explain <pkg>` or `yarn why <pkg>`.

## 3. Decide what to do with each advisory

Use the table in [references/decision.md](references/decision.md). In short: bump the direct dependency if you can, then a parent, then use an override, and accept the risk only with a reason and an expiry date. Show the user the decision for each advisory before you change anything.

## 4. Apply the change

Work on a new branch from the default branch (`chore/patch-<package>`). If the repo uses gh-stack, start it with `gh stack init`.

Requires (stack path only): the gh-stack GitHub CLI extension. If the repo uses stacked branches and `gh stack` is not installed, tell the user to run `gh extension install github/gh-stack`, then stop.

| Action | pnpm | npm | yarn (berry) |
|---|---|---|---|
| Bump a direct dependency | `pnpm up <pkg>@<ver>` (add `-r` or `--filter <ws>` in a workspace) | `npm install <pkg>@<ver>` (add `-w <ws>` in a workspace) | `yarn up <pkg>@<ver>` |
| Refresh a transitive dependency within its range | `pnpm up -r <pkg>` | `npm update <pkg>` | `yarn up -R <pkg>` |
| Override a version | `pnpm.overrides` in the root `package.json` | `overrides` in the root `package.json` | `resolutions` in the root `package.json` |
| Re-install after editing `package.json` | `pnpm install` | `npm install` | `yarn install` |

Use the package manager the lockfile belongs to. Pin an override to the smallest fixed version range, for example `"follow-redirects": "^1.15.6"`, and scope it to the parent when the manager allows (`"axios>follow-redirects"` in pnpm).

Record an accepted risk in the scanner config CI uses, usually `osv-scanner.toml`:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2027-02-01
reason = "Only reachable through the dev server proxy. No fix released yet."
```

## 5. Re-run the scan the way CI does

Run the exact command from the workflow, with the same flags and config. Then run the project's install, build and tests for the packages you touched. If an advisory still fails, go back to step 3 for that advisory.

## 6. Ticket (optional)

Skip this step when `ticket_in` is `none` or the user does not want a ticket.

Requires: Linear MCP, for this step only. If its tools are not available, tell the user the Linear MCP is missing and how to add it, then stop the ticket step and continue with step 7.

Create one issue per advisory in `linear_team`, with `security_project` and `security_label` when they are not `none`. Title: `Patch <package> for <CVE id>`. Put the advisory link, the decision and, for an accepted risk, the reason and expiry date in the description.

## 7. Commit and open the PR

One commit per package:

```
chore(deps): patch <package> for <CVE id>
```

Use the CVE id when the advisory has one, otherwise the GHSA id. The body is free-form: say what changed and why that option was chosen. Follow `ticket_in` for the ticket, as in the `commit` skill. For example:

```
chore(deps): patch follow-redirects for GHSA-xxxx-xxxx-xxxx

Override to ^1.15.6 under axios. @acme/http-client still pins axios 1.6
and has no release with the fix yet.

Refs: ORD-512
```

Open the PR with `gh pr create`, or `gh stack submit --auto` on a stack. In the description, list each advisory with its decision, and link the green scan run once CI has finished.
