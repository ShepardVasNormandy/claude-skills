# Auditing an Existing Skill

Act as a skill-design reviewer. The harness matches triggers on the frontmatter description, loads the SKILL.md body on invocation, and loads `references/` files only when read. Optimize for how the model behaves, not for how the prose reads.

## Contents

1. Read before judging
2. State the contract
3. Audit on five axes
4. Rank
5. Rewrite
6. Constraints

## 1. Read before judging

- Read SKILL.md in full, every file under `references/` (or equivalent), and every file under `scripts/` and `assets/`. Do not skim. Do not infer contents from filenames.
- Plugin skill: read the owning plugin's `.claude-plugin/plugin.json` for the namespace and version.
- Run `git log --oneline -- <skill-dir>` and skim recent commits. Churn points to instructions that kept failing. Not in a git repo (typical for a personal skill) → skip.
- Read the neighbours for axis B: the neighbour command from SKILL.md Step 1 for the skill's location, plus the available-skills list in your context (built-ins, anthropic-skills, superpowers).

## 2. State the contract (before any critique)

Write, in this order:

1. **Responsibility**: one sentence saying what the skill is accountable for.
2. **Out of scope**: what it must NOT do, as explicit non-goals. Derive them from the skill's text and mark inferred ones as inferred.
3. **Trigger surface**: the situations, phrasings and file contexts that should invoke it, and the near-neighbours that should not.
4. **Execution shape**: the steps, the tools called, the artifacts produced, and the hand-off or termination condition.
5. **Dependencies**: MCP servers, CLIs, env vars, repo layout, other skills.

Flag anything the files do not determine as UNSTATED. Do not guess.

## 3. Audit on five axes

Cite the exact SKILL.md line or block for every point.

- **A. Scope discipline**: where the model can overstep. Look for instructions that invite adjacent work, missing "stop here" boundaries, side effects (commits, posts, writes, deletes) with no confirmation gate, and creep into other skills' territory.
- **B. Trigger accuracy**: name concrete false positives and false negatives, with the phrasings that cause each.
- **C. Execution reliability**: ambiguous steps, unstated ordering, missing failure or empty-result branches, verification never demanded, decisions left to taste.
- **D. Token efficiency**: what sits in always-loaded context but belongs in `references/` behind a one-line pointer (long examples, tables, edge cases, boilerplate). Note what must stay inline.
- **E. Tool-call economy**: avoidable round-trips, such as sequential calls that could batch, repeated reads, and manual multi-step procedures that should be one script.

## 4. Rank

Output a table: Finding | Axis | Severity | Evidence (file:line) | Fix in one line. Order by severity, then by impact.

- **Must fix**: the skill produces wrong behaviour or oversteps its role.
- **Recommended**: it works but degrades reliably.
- **Optional**: polish.

## 5. Rewrite

Propose a complete SKILL.md that fixes every Must fix and Recommended finding. Say which Optional items were left out and why.

- Preserve the skill's purpose. Do not expand its remit.
- The description states when to use AND when not to use it.
- Include an explicit boundaries / non-goals section.
- Move anything not needed on every invocation into `references/`. List each proposed reference file with a one-line summary.
- Keep the author's voice and conventions where they are not the problem.

Present it as a diff against the current file, plus the full new file. Then continue with Step 3 of SKILL.md (confirm).

## 6. Constraints

- Write no file until the user approves the rewrite.
- Evidence before assertions: every claim cites a line actually read.
- Label speculative findings as speculative.
- Stay inside the target skill. List problems in neighbouring skills or the plugin under "Out of scope — noted, not acted on."
