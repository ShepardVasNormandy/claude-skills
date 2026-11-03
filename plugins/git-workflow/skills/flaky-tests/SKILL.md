---
name: flaky-tests
description: "Finds unreliable tests in GitHub Actions history. In unit mode it ranks tests by how often they fail across the last N runs of the CI test job and flags those that fail on more than one branch. In e2e mode it turns the failure annotations of recent E2E runs on the default branch into a Markdown report. Use it when CI goes red for no clear reason, when a test passes on rerun, or to decide which tests to quarantine first. Also available as /flaky-tests."
argument-hint: "[unit|e2e] [number-of-runs]"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/flaky-tests/scripts/*)
  - Read
---

# Flaky Tests

Two modes, both read-only against GitHub Actions through `gh` (authenticated) and `jq`:

- **`unit`** (default): rank Jest tests by how often they fail across recent runs of the CI test job.
- **`e2e`**: report flaky E2E tests from the failure annotations of recent runs of the E2E workflow on the default branch.

Pick the mode from the user's words (`e2e`, "end-to-end", "Playwright" → `e2e`; otherwise `unit`). When unsure, ask.

## Config

Read `.claude/git-workflow.local.md` in the project root. It is YAML front matter only.
For each key below that is missing, ask the user once, then write it to that file
(create the file if needed) before you continue. Never guess a value.

| Key | Meaning | Example |
|---|---|---|
| `test_workflow` | Workflow file whose runs execute the unit tests (`unit` mode) | `ci.yml` |
| `test_job` | Name of the test job as it appears in a run of that workflow (`unit` mode) | `checks / unit-tests` |
| `e2e_workflow` | Workflow file that runs the E2E tests (`e2e` mode) | `e2e.yml` |
| `e2e_job` | Optional, default: every job of the run. Name of the E2E job to read, when the workflow has other jobs (`e2e` mode) | `playwright` |

Optional keys are never asked for: use the default in their meaning.

Only the keys of the mode you run are needed; do not ask for the others. To help the user answer, list the workflows with `ls .github/workflows` and the job names of a recent run with `gh run view <run-id> --json jobs --jq '.jobs[].name'`. A job from a reusable workflow shows as `<caller job> / <called job>`. The repo is the current one (`gh repo view`).

## Mode `unit`

### How CI is usually wired (why the script targets a workflow and a job)

- Tests often run in a job of a reusable workflow (`workflow_call`), e.g. the `unit-tests` job of a `checks` workflow.
- A reusable workflow has **no runs of its own**. It is invoked by a caller such as `ci.yml`.
- So the job appears in the caller's runs under a combined name like **`checks / unit-tests`**. That is why `test_workflow` names the caller and `test_job` the combined job name.
- If CI runs only the tests of the packages a change touches, a run only executes those tests.

### Usage

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/flaky-tests/scripts/flaky-tests.sh [LIMIT]          # LIMIT defaults to 20
bash ${CLAUDE_PLUGIN_ROOT}/skills/flaky-tests/scripts/flaky-tests.sh [LIMIT] --json   # machine-readable output on stdout
```

Outputs:
- A per-run CSV at `/tmp/flaky-tests.csv` — columns `jobId,date,status,branch,failingTests` (failing tests joined with `|`).
- A grouped report on stdout (default), or a JSON array with `--json`.

The report has a summary header, then two sections:
- **LIKELY FLAKY** — tests that failed on **≥2 distinct branches** (the strong flaky signal).
- **SINGLE-BRANCH FAILURES** — failed on one branch only, usually a real break in that PR.

Within each section, tests are grouped by file (files ordered by their worst test). Every line shows `⚑<default-branch>` (e.g. `⚑main`) when it failed on the default branch and `(last seen YYYY-MM-DD)` (the most recent failure date). The **LIKELY FLAKY** lines additionally show a rate bar, `RATE (x/N)`, and the distinct-branch count (`3b`); the **SINGLE-BRANCH** lines omit the rate, since a failure rate over all runs is misleading for a one-branch break. Color is applied only on an interactive terminal: rate bar by severity (red/yellow), and the last-seen date **red if within the last 7 days** (active flake), **green if older** (likely already fixed).

JSON entries: `{test, file, count, total, rate, branchCount, branches[], failedOnMain, likelyFlaky, lastSeen}` (`lastSeen` is an ISO date; `failedOnMain` means the default branch).

Cancelled and still-running test jobs are excluded (they are not real results), so fewer than `LIMIT` runs may be examined. The denominator in the rate is the number of *examined* runs.

Runtime: runs are fetched in parallel, one worker per CPU by default (override with `JOBS`). The work is I/O-bound on `gh` latency, so concurrency helps a lot. Progress and status lines print to stderr; stdout stays clean for the report or JSON.

### How failing tests are parsed

`gh run view --job <id> --log-failed` returns the job log with a `job \t step \t timestamp+message` prefix. Jest prints, per failure:
- `FAIL <file> (<time> s)` — the failing test file
- `● <describe › test>` — the individual failing test

The script strips the log prefix, ties each `●` to its preceding `FAIL` file, and emits a uniform key:

```
src/services/orders/cancelOrder.test.ts::cancelOrder › should refund every paid line
```

Two quirks handled in the parser:
- Jest prints each failure twice (inline + "Summary of all failing tests"). Deduped per run.
- Path prefixes vary (`src/api/...` vs `api/...`). Deduped on a `src/`-stripped key, displaying the `src/` form.

### Reading the result (important caveat)

The rate is **failures / total test runs examined**, i.e. a *failure rate on recent PR runs*, not a proof of flakiness:
- The report already encodes this: trust the **LIKELY FLAKY** section (≥2 branches) over single-branch failures, which are usually that PR's own bug.
- `⚑main` means the test failed on the default branch itself, which is worth attention regardless of section.
- When CI runs only affected tests, a test absent from a run did not necessarily pass — it may not have run. So the denominator slightly over-counts; treat rates as a lower bound on flakiness.

### Overrides

Env vars override the config and defaults:
- `TEST_WORKFLOW`, `TEST_JOB` — override the config keys
- `REPO` (default: the current repo)
- `CSV` (default `/tmp/flaky-tests.csv`)
- `JOBS` (default = CPU count) — number of concurrent `gh` workers
- `NO_COLOR` — set to disable colored output

## Mode `e2e`

### Step 1: Fetch E2E run data

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/flaky-tests/scripts/fetch-e2e-annotations.sh [NUM_RUNS]
```

Default: last 30 runs if no argument provided. It reads the failure annotations (level `failure`, non-empty title, every page) of each run's jobs: only the job named `e2e_job` when it is set, otherwise every job, so sharded runs are covered. It deduplicates retries of the same test within a run, and prints a Markdown report: summary table, flaky test ranking, error patterns per test, and per-run detail with links. `E2E_WORKFLOW`, `E2E_JOB`, `REPO` and `BRANCH` env vars override the config, the current repo and the default branch.

### Step 2: Analyse and present

Read the Markdown output. Present to user with:

1. **Overall health**: how many runs failed out of total, trend direction
2. **Top flaky tests**: highlight tests that fail intermittently (not 100% failure rate, those are likely real bugs)
3. **Recommendations**: group by error pattern and suggest which tests need attention first
4. **Distinguish flaky vs broken**: tests failing 100% = likely broken, tests failing < 100% = flaky
