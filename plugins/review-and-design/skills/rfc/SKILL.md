---
name: rfc
description: Drafts a short design RFC for a planned change. Interviews the user one question at a time about the problem, goals, non-goals, constraints and options, reads the code the change touches, then writes the RFC as Markdown to the project's RFC folder and can publish it to Notion. Use when the user asks for an RFC, a design doc, a technical proposal or a write-up of a change before building it.
---

# RFC

Write a design RFC that a busy reviewer can read in ten minutes and answer with a clear yes, no or "change this".

## Config

Read `.claude/review-and-design.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `rfc_dir` | Optional, default `docs/rfc`. Folder the RFC file is written to. | `docs/design` |
| `rfc_publish` | Optional, default `none`. Where to publish after writing: `none` or `notion`. | `notion` |
| `rfc_notion_database` | Notion database the RFC page is created in. Needed only when `rfc_publish` is `notion`; ask for it only then. | `https://www.notion.so/team/RFCs-1a2b3c` |

Optional keys are never asked for: use the default in their meaning.

## Step 1: Interview

Ask one question per message and wait for the answer. Skip a question when the user already answered it. Stop once you can fill every required section. Cover, in this order:

1. The problem. What is broken or missing today, and who feels it? Ask for a number when one exists ("12% of refunds need manual handling").
2. Goals. What must be true when this ships?
3. Non-goals. What is out of scope on purpose, even if related?
4. Constraints. Deadlines, budgets, systems that cannot change, compliance rules.
5. Options. Which approaches were considered? What does the user lean towards, and why?
6. Unknowns. What does the user not know yet?

If an answer is vague, ask one follow-up that asks for an example. Do not ask more than two follow-ups on one topic. Write down what is still unclear as an open question instead.

## Step 2: Read the code

Before writing, read the code the change touches: entry points, data models, migrations, public API handlers, background jobs and the tests around them. Use what you find to:

- name real modules, tables and endpoints in the RFC;
- check the user's claims about current behaviour, and raise any mismatch with the user before writing;
- spot affected callers the user did not mention.

Cite files as `path/to/file.ext:line` so reviewers can check them.

## Step 3: Write the RFC

Derive a short kebab-case slug from the title, for example `partial-refunds`. Write the file to `<rfc_dir>/<slug>.md`. If that file exists, ask whether to overwrite it or pick another slug.

Use the template below. Drop optional sections that do not apply instead of writing "N/A". Use a diagram only when it explains something faster than prose; see `references/mermaid.md` for which type to pick and how to avoid rendering errors.

### Length limits

- The body, before any appendix, stays under roughly 1,500 words, which is one to three pages.
- The Summary is five sentences or fewer.
- Every other section fits in about 200 words or a single table. Anything longer goes to an appendix or a linked file.
- Two diagrams at most.
- Compare options in a table and list steps as a list. Delete any sentence that only repeats its heading or an earlier section.

### Template

```markdown
# RFC: <title>

- Status: Draft
- Author: <name>
- Date: <YYYY-MM-DD>
- Reviewers: <names or teams>

> How to review this: read the Summary and Proposal first. Then check Alternatives
> and Risks for anything you would decide differently. Leave comments on the exact
> line. Mark a comment "blocking" if the RFC must not be approved without a change.
> Answer the Open questions you can.

## Summary
<What we will build and why, in at most 5 sentences.>

## Context
<Current behaviour, with file references. The problem, with numbers where possible.>

## Goals
- <Measurable outcome>

## Non-goals
- <Related thing we will not do in this change>

## Proposal
<The design. Components, flow, and who calls whom. One diagram if it helps.>

## Alternatives considered
| Option | Pros | Cons | Why not chosen |
|---|---|---|---|

## Data model changes (optional)
<New or changed tables, columns, indexes and their migration. ER diagram if more than two tables move.>

## API changes (optional)
<New or changed endpoints, events or payloads. Mark breaking changes.>

## Rollout and migration
<Feature flag, backfill, order of deploys, how to roll back.>

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|

## Open questions
- <Question> (owner: <name>)
```

Write in plain sentences. State decisions as decisions. Keep "we could" for the Alternatives section.

### Example of the right level of detail

For an online store adding partial refunds, the Proposal section might read:

> Add a `refund_lines` table that links a refund to the order lines and quantities it covers. `POST /orders/{id}/refunds` accepts a list of `{line_id, quantity}` and rejects quantities above what was shipped and not yet refunded. The payment adapter refunds the summed amount in one call. Inventory is restocked per line only when the warehouse confirms the return.

## Step 4: Review with the user

Show the user the file path and a short outline (section names and the summary). Ask what to change. Apply the edits and stay within the length limits.

## Step 5: Publish (optional)

Skip this step when `rfc_publish` is `none`.

When `rfc_publish` is `notion`:

Requires: Notion MCP, for this publish step only. If its tools are not available, tell the user the RFC is saved locally at `<rfc_dir>/<slug>.md`, which server is missing and how to add it (`claude mcp add` with the Notion MCP server, or a plugin that ships it), then stop.

1. Ask the user to confirm before you create anything in Notion.
2. Create a page in `rfc_notion_database` with the RFC title as the page title and the Markdown body as content. Keep Mermaid blocks as code blocks with language `mermaid`.
3. Set a status property to Draft if the database has one.
4. Give the user the page link, and add it under the metadata list at the top of the local file.

The local file stays the source of truth. If the user edits the RFC later, update the file first, then the Notion page.
