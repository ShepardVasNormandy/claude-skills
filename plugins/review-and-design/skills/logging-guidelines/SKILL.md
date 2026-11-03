---
name: logging-guidelines
description: Applies a project's logging standards when writing or reviewing backend code. Checks structured JSON output, log levels, OpenTelemetry field names, trace correlation, redaction of secrets and personal data, sampling and message style, and fixes or flags what does not match. Use when adding or changing log statements, reviewing a diff that logs, setting up a logger, or when the user asks how something should be logged.
---

# Logging guidelines

Make log statements easy to search and understand when debugging production, and free of secrets and personal data.

## Config

Read `.claude/review-and-design.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `logging_guidelines` | Optional, default `references/guidelines.md` (the template shipped with this skill). Path, from the project root, to the project's own logging guidelines. When set, that file overrides the template. | `docs/engineering/logging.md` |

Optional keys are never asked for: use the default in their meaning.

## Load the rules

1. If `logging_guidelines` is set and the file exists, read it. It is the source of truth.
2. Otherwise read `references/guidelines.md` from this skill's directory.
3. If the project file exists but leaves a topic out (for example sampling), fall back to the template for that topic only and tell the user which topics came from the template.

To adopt the template for a project, copy `references/guidelines.md` into the repo, edit it, and set `logging_guidelines` to its path.

## Before you write or review

Find how the project logs today: the logger library, its setup file, any wrapper or helper, the redaction list and how trace context reaches the logger. Follow the existing helpers. Do not add a second logger.

## When writing code

- Log at boundaries and decisions: an incoming request or job, a call to another system, a branch that changes the outcome, a failure.
- Pick the level from the rules. Most new statements are `info` or `debug`.
- Put data in fields. Keep the message a short, constant phrase.
- Use the field names from the rules. Add a domain field (`order.id`, `refund.id`) when it helps find the event later.
- Never log a value the rules list as forbidden, even at `debug`. Pass it through the redaction helper or leave it out.
- Log an error once, where it is handled. Code that rethrows an error does not log it as well.

## When reviewing

Go through every added or changed log statement in the diff and check:

1. Is the output structured, with no string concatenation of values into the message?
2. Is the level right for what happened?
3. Are field names the agreed ones?
4. Does it carry trace context, either automatically or by an explicit field?
5. Could any field hold a secret, a token or personal data?
6. Is it inside a hot loop or per-item path that needs sampling or a summary line?
7. Is the same error logged at several layers?

Also flag missing logs: a caught error with no log and no rethrow, or a call to a payment, shipping or other external provider with no record of the outcome.

Report findings as `path:line`, the rule it breaks, and the fix. Group them by severity: leaks of secrets or personal data first, then wrong levels or missing error logs, then naming and style.
