---
name: update-project-skills
description: "Brings an installed plugin marketplace (claude-skills by default) up to date and reports what is different afterwards. Refreshes the marketplace, updates each plugin installed from it and prints the skills that were added, changed or removed, with a reminder to restart Claude Code. Use it through /update-project-skills, when a teammate mentions a new skill you do not have, when a skill looks out of date, or when asked to refresh the marketplace."
allowed-tools:
  - Bash(bash *update-project-skills.sh*)
  - Bash
---

# Update project skills

Updates a marketplace and the plugins installed from it, then prints the skills that were added, modified or removed.

Run the script from this skill's base directory (`<skill-dir>`, shown on invocation) and read its output back to the user. Pass a marketplace name when the user names one; otherwise it updates `claude-skills`:

```bash
bash <skill-dir>/scripts/update-project-skills.sh [marketplace]
```

It runs, in order:

1. Checks the marketplace is in `claude plugin marketplace list`. If it is not, it prints the `claude plugin marketplace add …` command and exits 1. Relay that command to the user and stop.
2. `claude plugin marketplace update <marketplace>`
3. `claude plugin update <plugin>@<marketplace>` for each plugin `claude plugin list` shows as installed from that marketplace. If none is installed, it prints the `claude plugin install <plugin>@<marketplace>` command and exits 0.

## Output

For each plugin, the script snapshots the skills of the newest cached version (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills`, or under `$CLAUDE_CONFIG_DIR` when set) before the update and diffs it against the newest version after:

```
git-workflow@claude-skills  (1.0.0 -> 1.1.0)
    ~ commit
agent-discipline@claude-skills  (1.2.0 -> 1.3.0)
    + update-project-skills

Legend: + added   ~ modified   - removed
```

If nothing changed, it says so and exits. A **Claude Code restart is required** for the updates to take effect in the running session, so remind the user.
