---
name: greet
description: Greets the user. Use when the test suite needs a config-using skill.
---

# Greet

Requires: Slack MCP. If its tools are not available, tell the user which server is missing and how to add it (`claude mcp add …` or the plugin that ships it).

## Config

Read `.claude/demo.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `greeting` | Word used to greet | `hello` |

## Steps

Post the greeting.
