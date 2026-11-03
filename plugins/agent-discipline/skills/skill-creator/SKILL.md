---
name: skill-creator
description: "Writes or reviews skills. It drafts a new SKILL.md with its scripts and references, or audits an existing skill for weak triggers, bloat and unclear steps. It works on skills in a marketplace plugin, in a repo's .claude/skills folder or in ~/.claude/skills. Use it to turn a repeated workflow into a skill, to find out why a skill never fires or fires too often, or to slim one down. It does not cover hooks, agents, commands or settings, and it does not review pull requests."
license: Complete terms in LICENSE.txt
---

# Skill Creator

Adapted from Anthropic's skill-creator (Apache-2.0, see LICENSE.txt); modified for this marketplace.

A skill is read by another Claude instance. Write only what that instance does not already know, and optimize for how it behaves, not for how the prose reads.

`<skill-dir>` is the directory holding this SKILL.md (the base directory shown on invocation). `<target>` is the skill being created or audited, and `<skills-root>` the directory that holds it:

| Location | Who gets it | `<skills-root>` |
|---|---|---|
| Plugin | Everyone who installs the plugin from the marketplace | `plugins/<plugin>/skills/` in the marketplace checkout |
| Project | Everyone working in that repo, once committed | `<repo>/.claude/skills/`; `<repo>` = `git rev-parse --show-toplevel` unless the user names another |
| Personal | Only the user, in every repo | `~/.claude/skills/` |

## Boundaries

- Settle the location first. The request or the existing skill's path decides it; otherwise ask with the table above.
- Plugin skill: check `test -f .claude-plugin/marketplace.json`. Fails → ask for the checkout path and stop until given.
- The request is an always-on behaviour (a hook → update-config)? Say so and stop.
- Touch only `<target>`. For a new plugin skill, also its row in a skill table of the plugin's or the root `README.md`, if such a table exists.
- Never edit another skill, agent, command, hook or settings file. List problems noticed there under "Out of scope — noted, not acted on" in the final report.
- Never perform the workflow the skill describes. Drafting a deploy skill is not deploying.
- Write nothing before the user approves in Step 3. Commit or push only when asked.

## Pick the mode

- New skill → Steps 1–5.
- Existing skill ("improve", "audit", "review", "fix triggering", "make leaner") → read `references/audit.md` and run it in place of Steps 1–2, then Steps 3–5 on the proposed rewrite.

## Step 1 — Understand with concrete examples

- Collect 2–3 real requests that should trigger the skill and one near-neighbour that should not. Ask with AskUserQuestion, at most 4 questions per round. Skip anything the conversation already answers.
- Settle: location (plugin: which plugin — each `plugins/<plugin>/.claude-plugin/plugin.json` description, or the README, says what it covers), invoker (user, Claude, or both), arguments.
- Check the name and read the neighbours in one command: `find <skills-root> -mindepth 2 -maxdepth 2 -name SKILL.md -exec grep -H '^description:' {} +`. Name taken → stop and ask. A description shown as `>` or `|` spans several lines: read that file's frontmatter. `<skills-root>` missing → no neighbours there; Step 4 creates it.
- Also scan the available-skills list in your context (built-ins, plugin skills, anthropic-skills, superpowers). Steer the new triggers clear of all of them.

## Step 2 — Plan contents

For each example, identify what would otherwise be rewritten on every run:

- Same code each time → `scripts/`. Deterministic, runs without entering context.
- Schemas, API docs, long tables, edge cases, anything needed on a minority of runs → `references/<topic>.md`.
- Files copied into the output → `assets/`.
- Unsure how to split content? Read `references/skill-anatomy.md`.

## Step 3 — Draft and confirm

Frontmatter — include a field only when it changes behaviour:

| Field | Use when |
|---|---|
| `name` | Always; equals the directory name. |
| `description` | Always. Rules below. |
| `argument-hint` | The skill takes arguments. |
| `disable-model-invocation: true` | Side-effecting or deliberate workflow; user-triggered only. |
| `allowed-tools` | Specific tools should be pre-approved for the invoking turn. |
| `user-invocable: false` | Claude-only background knowledge; hidden from the slash menu. |
| `license` | Vendored third-party skills only. |

Description:
- Third person, verb first, primary use case first. Hard cap 1,024 characters; `quick_validate.py` rejects more.
- Trigger phrases the user would actually type, verbatim.
- At least one non-trigger naming the neighbour it would otherwise steal. Name only skills every user of this skill has.
- With `disable-model-invocation: true`, describe only the explicit command.
- All when-to-use information goes here, never in the body.

Body:
- Imperative. Under 500 lines; aim far shorter. Delete any line that would not change behaviour.
- A Boundaries section: what it must not touch, when it stops, and a confirmation gate before every side effect (write, commit, post, delete).
- A branch for every step that can fail or return nothing.
- Link every `references/` file from SKILL.md with when to read it. Keep them one level deep; add a table of contents above 100 lines.
- No README, CHANGELOG or INSTALL files inside the skill.
- Plugin or project skill: never mention a personal skill (anything in `~/.claude/skills`) in the description or body. Teammates do not have them.
- Multi-step or branching flows: see `references/workflows.md`. Fixed output formats or examples: see `references/output-patterns.md`.

Print the full SKILL.md, every path to be written (for a new plugin skill, including the README row), and for an existing skill the diff. In audit mode the audit already printed the rewrite and diff: print only the remaining paths. Wait. Edits requested → revise and reprint. Declined → stop.

## Step 4 — Write and verify

- Write the files directly.
- Scripts added: run a script only if it is read-only. If it writes outside a temp dir, posts, deploys, mutates git/gh or calls an API with side effects, check syntax only (`bash -n`, `python3 -m py_compile`, `node --check`) and ask before a real run.
- Run `python3 <skill-dir>/scripts/quick_validate.py <target>`. It checks frontmatter keys, `name` = directory, description ≤ 1,024 characters, and that every `references/` path named in SKILL.md exists (plus `scripts/` and `assets/` paths when the skill ships that directory).
- Fix and re-verify. Report any failure you cannot fix.

## Step 5 — Ship

Project or personal skill → skip to the report: files written, the command `/<name>`, one prompt that should auto-trigger it (omit if `disable-model-invocation: true`), and that a new session is the reliable test. Project skill: teammates get it once it is committed; commit only when asked.

Plugin skill:
- Version: bump `version` in `plugins/<plugin>/.claude-plugin/plugin.json`. Patch for a fix, minor for a new skill, major for a rename or removal. Claude Code caches plugins by version: without a bump, `claude plugin update` and `/update-project-skills` keep the old copy.
- New skill: add its row to the README skill table, if one exists.
- Report: files changed, new version, the command `/<namespace>:<name>` (namespace = plugin.json `name`), one prompt that should auto-trigger it (omit if `disable-model-invocation: true`), how to test now (`claude --plugin-dir ./plugins/<plugin-dir>`, then `/reload-plugins` after edits), and that others get it after merge with `claude plugin update <plugin>@<marketplace>` or `/update-project-skills`.
- Commit only when asked: `feat(<namespace>): <what>`, or `fix(...)` for fixes.

Stop.
