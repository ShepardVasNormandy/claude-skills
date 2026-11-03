#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fetch-e2e-annotations.sh [NUM_RUNS]

Fetches the last NUM_RUNS (default 30) runs of the E2E workflow on the default
branch and prints a Markdown flakiness report built from the failure annotations
of each run.

Settings come from .claude/git-workflow.local.md in the main worktree; the upper-case
env var of the same name overrides it:
  e2e_workflow  workflow file that runs the E2E tests, e.g. e2e.yml
  e2e_job       optional: only read the job with this name (default: every job)

Other env vars:
  REPO    owner/name (default: the current repo, from gh repo view)
  BRANCH  branch to analyse (default: the repo's default branch)
EOF
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac

NUM_RUNS="${1:-30}"
MAIN_WORKTREE=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{ print substr($0, 10); exit }' || true)

# Prints the value of a key from the config front matter, one line per list item.
config_get() {
  local file="$MAIN_WORKTREE/.claude/git-workflow.local.md"
  [ -n "$MAIN_WORKTREE" ] && [ -f "$file" ] || return 0
  awk -v key="$1" -v q="'" '
    function emit(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); gsub("^[\"" q "]|[\"" q "]$", "", v); if (v != "") print v }
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[ \t]*$/) exit; next }
    /^---[ \t]*$/ { exit }
    list && /^[ \t]*- / { sub(/^[ \t]*- /, ""); emit($0); next }
    list { exit }
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v == "") { list = 1; next }
      if (v ~ /^\[.*\]$/) { n = split(substr(v, 2, length(v) - 2), a, ","); for (i = 1; i <= n; i++) emit(a[i]); exit }
      emit(v); exit
    }' "$file"
}

WORKFLOW="${E2E_WORKFLOW:-$(config_get e2e_workflow)}"
if [ -z "$WORKFLOW" ]; then
  echo "Missing e2e_workflow: set it in .claude/git-workflow.local.md, or export E2E_WORKFLOW." >&2
  exit 1
fi
JOB="${E2E_JOB:-$(config_get e2e_job)}"
REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
BRANCH="${BRANCH:-$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)}"

# Step 1: List recent runs
RUNS=$(gh run list -w "$WORKFLOW" -b "$BRANCH" -R "$REPO" -L "$NUM_RUNS" \
  --json databaseId,conclusion,createdAt,attempt)

TOTAL_RUNS=$(echo "$RUNS" | jq 'length')

if [ "$TOTAL_RUNS" -eq 0 ]; then
  echo "No E2E runs found."
  exit 0
fi

# Step 2: Collect annotations from all runs
ALL_FAILURES="[]"
RUN_DETAILS="[]"

for i in $(seq 0 $((TOTAL_RUNS - 1))); do
  RUN_ID=$(echo "$RUNS" | jq -r ".[$i].databaseId")
  CONCLUSION=$(echo "$RUNS" | jq -r ".[$i].conclusion")
  CREATED_AT=$(echo "$RUNS" | jq -r ".[$i].createdAt")
  ATTEMPT=$(echo "$RUNS" | jq -r ".[$i].attempt")

  JOB_IDS=$(gh api "repos/$REPO/actions/runs/$RUN_ID/attempts/$ATTEMPT/jobs" --paginate 2>/dev/null |
    jq -r --arg name "$JOB" '.jobs[] | select($name == "" or .name == $name) | .id' 2>/dev/null || true)

  # Retries produce several annotations for the same test in one run: keep one per title.
  FAILED_TESTS="[]"
  if [ -n "$JOB_IDS" ]; then
    FAILED_TESTS=$(for JOB_ID in $JOB_IDS; do
        gh api "repos/$REPO/check-runs/$JOB_ID/annotations" --paginate 2>/dev/null || true
      done | jq -s '[.[][] | select(.annotation_level == "failure" and .title != "" and .title != null)]
        | group_by(.title)
        | map(.[0])' 2>/dev/null || echo "[]")
  fi

  FAIL_COUNT=$(echo "$FAILED_TESTS" | jq 'length')

  # Add run detail
  RUN_DETAILS=$(echo "$RUN_DETAILS" | jq \
    --arg id "$RUN_ID" \
    --arg conclusion "$CONCLUSION" \
    --arg date "$CREATED_AT" \
    --arg attempt "$ATTEMPT" \
    --argjson failCount "$FAIL_COUNT" \
    --argjson failures "$FAILED_TESTS" \
    '. + [{runId: $id, conclusion: $conclusion, date: $date, attempt: ($attempt | tonumber), failCount: $failCount, failures: $failures}]')

  # Accumulate all failures with run context
  if [ "$FAIL_COUNT" -gt 0 ]; then
    TAGGED=$(echo "$FAILED_TESTS" | jq --arg runId "$RUN_ID" --arg date "$CREATED_AT" \
      '[.[] | . + {runId: $runId, runDate: $date}]')
    ALL_FAILURES=$(echo "$ALL_FAILURES $TAGGED" | jq -s '.[0] + .[1]')
  fi
done

# Step 3: Compute statistics
FAILED_RUNS=$(echo "$RUN_DETAILS" | jq '[.[] | select(.conclusion == "failure")] | length')
PASSED_RUNS=$((TOTAL_RUNS - FAILED_RUNS))

# Group failures by test name and compute per-test stats
TEST_STATS=$(echo "$ALL_FAILURES" | jq --argjson total "$TOTAL_RUNS" '
  group_by(.title)
  | map({
      test: .[0].title,
      file: (.[0].title | split(" > ")[0]),
      failCount: ([.[].runId] | unique | length),
      totalRuns: $total,
      failRate: ((([.[].runId] | unique | length) / $total * 100) | round),
      runIds: [.[].runId] | unique,
      errors: [.[].message] | unique
    })
  | sort_by(-.failCount)
')

# Step 4: Output Markdown report
echo "# E2E Flakiness Report"
echo ""
echo "**Workflow:** $WORKFLOW | **Branch:** $BRANCH | **Runs analysed:** $TOTAL_RUNS"
echo ""

echo "## Summary"
echo ""
echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Total runs | $TOTAL_RUNS |"
echo "| Failed runs | $FAILED_RUNS |"
echo "| Passed runs | $PASSED_RUNS |"
FAIL_RATE=$(awk -v f="$FAILED_RUNS" -v t="$TOTAL_RUNS" 'BEGIN { printf "%.1f", f * 100 / t }')
echo "| Run failure rate | ${FAIL_RATE}% |"
UNIQUE_TESTS=$(echo "$TEST_STATS" | jq 'length')
echo "| Unique failing tests | $UNIQUE_TESTS |"
echo ""

echo "## Flaky Test Ranking"
echo ""
if [ "$UNIQUE_TESTS" -eq 0 ]; then
  echo "No test failures found across $TOTAL_RUNS runs."
else
  echo "| # | Test | File | Failures | Rate |"
  echo "|---|------|------|----------|------|"
  echo "$TEST_STATS" | jq -r '
    to_entries[]
    | "| \(.key + 1) | \(.value.test | split(" > ")[1:] | join(" > ")) | \(.value.file) | \(.value.failCount)/'"$TOTAL_RUNS"' | \(.value.failRate)% |"
  '
fi
echo ""

echo "## Error Patterns"
echo ""
echo "$TEST_STATS" | jq -r '
  .[] |
  "### \(.test | split(" > ")[1:] | join(" > "))\n" +
  "- **File:** `\(.file)`\n" +
  "- **Failure rate:** \(.failRate)% (\(.failCount)/\(.totalRuns) runs)\n" +
  "- **Failed in runs:** \(.runIds | join(", "))\n" +
  "\n**Errors:**\n" +
  (.errors | map("```\n" + . + "```") | join("\n")) +
  "\n"
'

echo "## Per-Run Detail"
echo ""
echo "| # | Date | Run ID | Conclusion | Failed tests |"
echo "|---|------|--------|------------|--------------|"
echo "$RUN_DETAILS" | jq -r '
  to_entries[]
  | "| \(.key + 1) | \(.value.date) | [\(.value.runId)](https://github.com/'"$REPO"'/actions/runs/\(.value.runId)) | \(.value.conclusion) | \(.value.failCount) |"
'
