# review-and-design configuration

Skills in the `review-and-design` plugin read these keys from `.claude/review-and-design.local.md` in the project root (YAML front matter only). A skill asks for a missing key once, writes it to that file, and continues. Optional keys are never asked for; the skill uses the default.

| Key | Used by | Meaning | Example |
|---|---|---|---|
| `rfc_dir` | rfc | Optional, default `docs/rfc`. Folder the RFC is written to, as `<rfc_dir>/<slug>.md`. | `docs/design` |
| `rfc_publish` | rfc | Optional, default `none`. Where to publish the RFC after writing it: `none` or `notion`. | `notion` |
| `rfc_notion_database` | rfc | Notion database the RFC page is created in. Required only when `rfc_publish` is `notion`. | `https://www.notion.so/team/RFCs-1a2b3c` |
| `logging_guidelines` | logging-guidelines | Optional, default `references/guidelines.md` (the template shipped with the skill). Path from the project root to the project's own logging guidelines, which then override the template. | `docs/engineering/logging.md` |

`address-pr-feedback` and `decision-deck` use no config keys.

## Example

```markdown
---
rfc_dir: docs/design
rfc_publish: notion
rfc_notion_database: "https://www.notion.so/team/RFCs-1a2b3c"
logging_guidelines: docs/engineering/logging.md
---
```
