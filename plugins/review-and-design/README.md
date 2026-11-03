# review-and-design

Skills for reviewing and designing software: senior reviewers for backend, frontend and UX, working through PR feedback, RFCs, decision decks and logging standards.

## Install

```
claude plugin marketplace add ShepardVasNormandy/claude-skills
claude plugin install review-and-design@claude-skills
```

## Skills

| Skill | What it does |
|---|---|
| `reviewer-backend` | Senior backend reviewer for a design, diff or plan: transactions, idempotency, concurrency, timeouts as unknown outcomes, external side effects, migrations, authorization, observability and failure tests. Findings are ranked must fix, recommended or optional. |
| `reviewer-frontend` | Senior frontend reviewer: query keys and invalidation, mutation safety, loading, error and empty states, trust boundaries, forms, accessibility, rendering cost, error reporting and test levels. |
| `reviewer-ux` | Senior UX reviewer for a design, prototype or diff: users and goals, main flow and edge cases, irreversible actions, error recovery, every screen state, wording, accessibility and a novice and expert pass. |
| `address-pr-feedback` | Fetches the unresolved review threads on your PR, groups them, proposes a fix or a reply for each, applies fixes only after you agree and drafts the replies. |
| `rfc` | Interviews you on a planned change, reads the code it touches and writes a short design RFC to `docs/rfc/<slug>.md`. Can publish it to Notion. |
| `decision-deck` | Builds a short decision deck for an architecture review from an RFC file, pasted text, a Notion page or an interview, and checks every claim against the source. Output is a Slides artifact, or an HTML file when no Artifact tool is available. |
| `logging-guidelines` | Applies logging standards when writing or reviewing backend code: structured JSON, levels, OpenTelemetry field names, trace correlation, redaction and sampling. Ships a template you can copy and adapt. |

## Config

The skills read `.claude/review-and-design.local.md` in your project. Keys: `rfc_dir`, `rfc_publish`, `rfc_notion_database`, `logging_guidelines`. All are optional unless `rfc_publish` is `notion`. See [docs/configuration/review-and-design.md](../../docs/configuration/review-and-design.md). Add `*.local.md` to your `.gitignore` if the values are personal.

## Requirements

- `gh` CLI, authenticated, and `jq`: `address-pr-feedback`.
- Notion MCP: `rfc` when `rfc_publish` is `notion`, and `decision-deck` when you give it a Notion RFC URL.

The other skills need no MCP server.
