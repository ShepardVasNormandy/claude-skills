# claude-skills

A marketplace of Claude Code skills for everyday engineering work: git workflow, working with agents, code review and design, and team routines. The skills don't assume a particular stack or company. Anything specific to your team, such as the ticket format, the tracker, or where RFCs go, lives in a small config file in each project, so the same skills fit different teams. Each skill is a Markdown file with scripts and references next to it, so you can read what it does, change it, or copy it into your own repo.

There are 4 plugins with 21 skills in total.

## Install

```
claude plugin marketplace add ShepardVasNormandy/claude-skills
claude plugin install <plugin>@claude-skills
```

Replace `<plugin>` with one of the names below, for example `claude plugin install git-workflow@claude-skills`. Each plugin installs on its own.

## Plugins

| Plugin | Skills | Guide |
|---|---|---|
| `git-workflow` | 8 | [plugins/git-workflow](plugins/git-workflow/README.md) |
| `agent-discipline` | 5 | [plugins/agent-discipline](plugins/agent-discipline/README.md) |
| `review-and-design` | 7 | [plugins/review-and-design](plugins/review-and-design/README.md) |
| `team-workflow` | 1 | [plugins/team-workflow](plugins/team-workflow/README.md) |

### git-workflow

| Skill | What it does |
|---|---|
| `add-worktree` | Sets up a branch in its own folder beside the main checkout, with the gitignored files it needs (dependencies, `.env` files) copied over. |
| `remove-worktree` | Cleans up a worktree and its local branch once the PR is merged. It stops if the worktree has uncommitted or unpushed work. |
| `stack` | Manages stacked branches and PRs with `gh stack`, and prints the CI and review status of the stack. |
| `gh-pr-status` | Reports your open PRs and the PRs waiting for your review, with CI status and unresolved thread counts. |
| `commit` | Commits the current work with a Conventional Commits message, scoped to the changed packages, with an optional ticket trailer. Works with stacked branches through `gh stack`. |
| `changeset` | Writes Changesets entries for the changed packages of a JavaScript or TypeScript monorepo, with the bump type and a one-line summary each. |
| `fix-osv` | Gets a failing OSV scan passing: picks a fix for each advisory, reruns the scan and opens a PR. |
| `flaky-tests` | Ranks unreliable unit tests from recent CI runs, or writes a report from failing E2E runs. |

### agent-discipline

| Skill | What it does |
|---|---|
| `no-side-quests` | Holds a task to its stated scope. Unrelated problems it spots are listed for you at the end, untouched. |
| `asd-ste100` | Rewrites text in Simplified Technical English so a reader or another agent cannot misread it. |
| `model-router` | Splits a request into independent tasks and runs one sub-agent per task, each on a suitable model. |
| `skill-creator` | Drafts a new skill or reviews an existing one for weak triggers and bloat. |
| `update-project-skills` | Refreshes the marketplace and its installed plugins, then lists which skills changed. |

### review-and-design

| Skill | What it does |
|---|---|
| `reviewer-backend` | Reviews a backend design, diff or plan as a senior engineer: transactions, idempotency, concurrency, timeouts, side effects, migrations, authorization and failure tests. |
| `reviewer-frontend` | Reviews frontend work as a senior engineer: query keys and invalidation, mutation safety, UI states, trust boundaries, forms, accessibility and rendering cost. |
| `reviewer-ux` | Reviews a design, prototype or diff as a senior UX designer: user goals, flows, irreversible actions, error recovery, every screen state and wording. |
| `address-pr-feedback` | Fetches the unresolved review threads on your PR, groups them, proposes a fix or a reply for each, applies fixes after you agree and drafts the replies. |
| `rfc` | Interviews you on a planned change, reads the code it touches and writes a short design RFC. Can publish it to Notion. |
| `decision-deck` | Builds a short decision deck from an RFC file, pasted text, a Notion page or an interview, and checks every claim against the source. |
| `logging-guidelines` | Applies logging standards when you write or review backend code: structured JSON, levels, OpenTelemetry field names, trace correlation and redaction. The bundled default is a template. |

### team-workflow

| Skill | What it does |
|---|---|
| `inbox` | Gathers your open tickets, Slack messages waiting for a reply and PR review requests into one HTML to-do page. |

## Configuration

Skills that need project values, such as a ticket format or a Notion database, read them from `.claude/<plugin>.local.md` in the project where you use them. The file holds YAML front matter only. When a key is missing, the skill asks for it once and saves the answer. Keys for each plugin are listed in [docs/configuration](docs/configuration/README.md).

Add `*.local.md` to your `.gitignore` if the values are personal.

## Requirements

Most skills only read and edit files in your repo. These need something more:

| Needs | Skills |
|---|---|
| Linear MCP | `fix-osv` (ticket step); `inbox` when configured for Linear |
| Atlassian (Jira) MCP | `inbox` when configured for Jira |
| Slack MCP | `inbox` uses it when present |
| Notion MCP | `rfc` when `rfc_publish` is `notion`; `decision-deck` for a Notion RFC URL |
| `gh` CLI | `gh-pr-status`, `flaky-tests`, `address-pr-feedback`, `fix-osv`, `changeset`; `inbox` when configured for GitHub Issues; `inbox` also uses it for PRs when present |
| gh-stack extension | `stack`; `commit` and `fix-osv` when the repo uses stacked branches |
| osv-scanner | `fix-osv` |
| jq | `gh-pr-status`, `flaky-tests`, `stack`, `address-pr-feedback` |
| node or python3 | `flaky-tests`; node alone for `model-router`; python3 alone for `inbox` and `skill-creator` |

A skill that needs an MCP server says so on a `Requires:` line and stops with instructions if the server is missing.

## Extend it

To add a skill, create `plugins/<plugin>/skills/<name>/SKILL.md` with `name` and `description` in the front matter. The `skill-creator` skill in `agent-discipline` can draft one for you. Put scripts in `scripts/` and longer material in `references/` next to the `SKILL.md`. If the skill reads project values, follow the config block described in [docs/configuration](docs/configuration/README.md) and list its keys in the plugin's file there.

To add a plugin, create `plugins/<name>/.claude-plugin/plugin.json`, add the skills under `plugins/<name>/skills/`, and list the plugin in `.claude-plugin/marketplace.json` with `"source": "./plugins/<name>"`.

Run the checks before you commit:

```
bash tests/run.sh
scripts/validate.sh
scripts/check-leaks.sh
```

`tests/run.sh` runs the repo's tests and the config contract. `scripts/validate.sh` checks the manifests, front matter and script portability. `scripts/check-leaks.sh` searches the repo for terms that should not be published: company and product names, people's names, Notion, Linear and Slack ids, and any phrases you list. It ships with placeholder lists only. Put the names you must never publish in `.leak-terms.local` at the repo root, one per line. The file is git-ignored, so the list itself is never published:

```
# lines starting with # are ignored
term: mycompany
term: falcon
name: Jane
phrase: ship it friday
allow: falcon-(cli|sdk)
```

`term:` entries are matched as company names, `name:` entries as people's names, `phrase:` entries as text that starts at a word boundary. Each value is an extended regex, matched without regard to case.

`allow:` entries handle a term that is also an ordinary word or library name. Each one is an extended regex, matched with case, and whatever it matches is blanked out of the line before the term and name rules run. The rest of the line is still checked, so with `term: falcon`, `allow: falcon-(cli|sdk)` lets "builds run on falcon-cli and falcon-sdk" through but still flags "ask the Falcon team" on the same line. A configured term followed by a dash and digits is always flagged.

For CI, put the same lists in the `LEAK_TERMS`, `LEAK_NAMES` and `LEAK_PHRASES` environment variables, pipe-separated (`mycompany|falcon`), and the allowed matches in `LEAK_ALLOW` as one regex (`falcon-(cli|sdk)`). The checks workflow reads them from repository secrets of the same names. All sources add to the built-in lists.

## Credits

`plugins/agent-discipline/skills/skill-creator` is based on Anthropic's skill-creator and keeps its Apache-2.0 license. See [LICENSE.txt](plugins/agent-discipline/skills/skill-creator/LICENSE.txt).

## License

MIT. See [LICENSE](LICENSE).
