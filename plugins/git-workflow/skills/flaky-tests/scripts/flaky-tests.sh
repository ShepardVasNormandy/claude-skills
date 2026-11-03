#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: flaky-tests.sh [LIMIT] [--json]

Collects failing Jest tests across the last LIMIT (default 20) runs of the CI test
job and ranks them by failure rate. Writes a per-run CSV and prints a ranked report,
or a JSON array with --json. Runs are fetched in parallel.

Settings come from .claude/git-workflow.local.md in the main worktree; the upper-case
env var of the same name overrides each one:
  test_workflow  workflow file that runs the tests, e.g. ci.yml
  test_job       job name as shown in a run, e.g. "checks / unit-tests"

Other env vars:
  REPO      owner/name (default: the current repo, from gh repo view)
  CSV       per-run CSV path (default: /tmp/flaky-tests.csv)
  JOBS      concurrent gh workers (default: CPU count)
  NO_COLOR  disable colored output
EOF
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
esac

CSV="${CSV:-/tmp/flaky-tests.csv}"

# Extract failing tests from a job log (read on stdin). Jest prints each failure
# twice (inline + summary) and path prefixes vary (src/api vs api); dedup per run
# on a src/-stripped key, keeping the first-seen (src/) display form.
parse_failing_tests() {
  awk -F'\t' '
    { msg=$3; sub(/^[0-9T:.Z -]+ /,"",msg)
      if (msg ~ /^FAIL /) { f=msg; sub(/^FAIL /,"",f); sub(/ \([0-9.]+ s\)$/,"",f); curfile=f }
      if (msg ~ /^[[:space:]]*● /) {
        t=msg; sub(/^[[:space:]]*● /,"",t)
        key=curfile "::" t; norm=key; sub(/^src\//,"",norm)
        if (!(norm in seen)) { seen[norm]=1; print key }
      }
    }'
}

# ---- Worker mode: process a single run (invoked via xargs) -------------------
if [ "${1:-}" = "__worker" ]; then
  idx="$2"
  row=$(awk -F'\t' -v i="$idx" '$1==i{print;exit}' "$RUNS_FILE")
  IFS=$'\t' read -r _ run date branch <<< "$row"

  job=$(gh run view "$run" --repo "$REPO" --json jobs \
    --jq ".jobs[] | select(.name==\"$TEST_JOB\") | {id:.databaseId,conclusion}" 2>/dev/null || true)
  if [ -z "$job" ]; then
    printf '  run %s — no test job, skipped\n' "$run" >&2
    exit 0
  fi
  jobId=$(echo "$job" | jq -r .id)
  status=$(echo "$job" | jq -r .conclusion)

  # Exclude cancelled / still-running jobs: they are not real results and would
  # dilute the failure-rate denominator.
  if [ "$status" = "cancelled" ] || [ "$status" = "null" ] || [ -z "$status" ]; then
    printf '  run %s — %s, excluded\n' "$run" "$status" >&2
    exit 0
  fi

  tests=""
  if [ "$status" = "failure" ]; then
    tests=$(gh run view --repo "$REPO" --job "$jobId" --log-failed 2>/dev/null | parse_failing_tests || true)
    # Store "branch \t date \t test" so aggregation can count distinct branches
    # and track the most recent failure date per test.
    echo "$tests" | grep -v '^$' | awk -v b="$branch" -v d="$date" 'BEGIN{OFS="\t"}{print b,d,$0}' > "$OUTDIR/fails.$idx" || true
    nfail=$(echo "$tests" | grep -vc '^$' || true)
    printf '  run %s — failure, %d failing test(s)\n' "$run" "$nfail" >&2
  else
    printf '  run %s — %s\n' "$run" "$status" >&2
  fi

  joined=$(echo "$tests" | grep -v '^$' | paste -sd'|' - || true)
  joined=${joined//\"/\"\"}   # double inner quotes for valid CSV
  printf '%s,%s,%s,%s,"%s"\n' "$jobId" "$date" "$status" "$branch" "$joined" > "$OUTDIR/csv.$idx"
  exit 0
fi

# ---- Main --------------------------------------------------------------------
LIMIT=20
JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    [0-9]*) LIMIT="$a" ;;
  esac
done
NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
JOBS="${JOBS:-$NCPU}"

# Color only on an interactive terminal (and not in JSON mode).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$JSON" = 0 ]; then COLOR=1; else COLOR=0; fi

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

TEST_WORKFLOW="${TEST_WORKFLOW:-$(config_get test_workflow)}"
TEST_JOB="${TEST_JOB:-$(config_get test_job)}"
if [ -z "$TEST_WORKFLOW" ] || [ -z "$TEST_JOB" ]; then
  echo "Missing test_workflow or test_job: set them in .claude/git-workflow.local.md, or export TEST_WORKFLOW and TEST_JOB." >&2
  exit 1
fi
REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)

OUTDIR="$(mktemp -d)"
RUNS_FILE="$(mktemp)"
export REPO TEST_JOB OUTDIR RUNS_FILE

echo "Fetching last $LIMIT $TEST_WORKFLOW runs from $REPO (parallel: $JOBS workers) ..." >&2
gh run list --repo "$REPO" --workflow "$TEST_WORKFLOW" --limit "$LIMIT" \
  --json databaseId,createdAt,headBranch \
  --jq '.[] | [.databaseId, .createdAt, .headBranch] | @tsv' \
  | awk 'BEGIN{OFS="\t"} {printf "%04d\t%s\n", NR, $0}' > "$RUNS_FILE"

# Fan out: one worker per run, capped at $JOBS concurrent.
awk -F'\t' '{print $1}' "$RUNS_FILE" \
  | xargs -P "$JOBS" -I{} "$0" __worker {} || true

# Aggregate in run order (idx zero-padded → lexical sort = date DESC).
echo "jobId,date,status,branch,failingTests" > "$CSV"
cat "$OUTDIR"/csv.* 2>/dev/null >> "$CSV" || true
FAILS_FILE="$(mktemp)"   # lines: "branch \t date \t test"
cat "$OUTDIR"/fails.* 2>/dev/null > "$FAILS_FILE" || true
TOTAL=$(find "$OUTDIR" -name 'csv.*' | wc -l | tr -d ' ')
FAILED=$(find "$OUTDIR" -name 'fails.*' | wc -l | tr -d ' ')

rm -rf "$OUTDIR" "$RUNS_FILE"
echo "Done. $TOTAL test runs examined." >&2
echo "CSV written to $CSV" >&2

if [ "$TOTAL" -eq 0 ]; then echo "No completed test runs found." >&2; rm -f "$FAILS_FILE"; exit 0; fi

# One record per test, sorted: flaky section first, then file (by worst test), then rate.
# Fields: flag \t fileRank \t file \t count \t nbranch \t onMain \t disp \t branchList \t lastSeen
RECORDS="$(mktemp)"
awk -F'\t' -v main="$DEFAULT_BRANCH" '
  { br=$1; dt=$2; key=$3; norm=key; sub(/^src\//,"",norm)
    cnt[norm]++
    if (!(norm in disp) || key ~ /^src\//) disp[norm]=key
    if (dt>ls[norm]) ls[norm]=dt
    bk=norm SUBSEP br
    if (!(bk in sb)) { sb[bk]=1; nbr[norm]++; bl[norm]=bl[norm] (bl[norm]==""?"":",") br }
    if (br==main) om[norm]=1 }
  END {
    for (n in cnt) { f=disp[n]; s=index(f,"::"); file=(s?substr(f,1,s-1):f)
                     tfile[n]=file; if (cnt[n]>fmax[file]) fmax[file]=cnt[n] }
    for (n in cnt) printf "%d\t%d\t%s\t%d\t%d\t%d\t%s\t%s\t%s\n",
      (nbr[n]>=2?1:0), fmax[tfile[n]], tfile[n], cnt[n], nbr[n], (om[n]?1:0), disp[n], bl[n], ls[n]
  }' "$FAILS_FILE" \
| sort -t$'\t' -k1,1nr -k2,2nr -k3,3 -k4,4nr > "$RECORDS"

rm -f "$FAILS_FILE"
DISTINCT=$(wc -l < "$RECORDS" | tr -d ' ')
FLAKY=$(awk -F'\t' '$1==1' "$RECORDS" | wc -l | tr -d ' ')

if [ "$JSON" = 1 ]; then
  awk -F'\t' -v total="$TOTAL" '
    function esc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }
    BEGIN { print "["; first=1 }
    { disp=$7; sep=index(disp,"::"); test=(sep?substr(disp,sep+2):disp)
      file=$3; n=split($8,arr,","); bl=""
      for (i=1;i<=n;i++) bl=bl (i>1?",":"") "\"" esc(arr[i]) "\""
      split($9,ds,"T")
      if (!first) print ","; first=0
      printf "  {\"test\":\"%s\",\"file\":\"%s\",\"count\":%d,\"total\":%d,\"rate\":%.1f,\"branchCount\":%d,\"branches\":[%s],\"failedOnMain\":%s,\"likelyFlaky\":%s,\"lastSeen\":\"%s\"}",
        esc(test), esc(file), $4, total, ($4/total)*100, $5, bl, ($6=="1"?"true":"false"), ($1=="1"?"true":"false"), ds[1] }
    END { print ""; print "]" }' "$RECORDS"
  rm -f "$RECORDS"
  exit 0
fi

echo
printf '%sFlaky test report%s\n' "$([ "$COLOR" = 1 ] && printf '\033[1m')" "$([ "$COLOR" = 1 ] && printf '\033[0m')"
echo "$TOTAL runs · $FAILED failed · $DISTINCT failing tests · $FLAKY likely flaky"

# Recency threshold: last seen within a week → red (active), older → green (likely stale).
CUTOFF=$(node -e 'console.log(new Date(Date.now() - 7 * 864e5).toISOString().slice(0, 10))' 2>/dev/null ||
  python3 -c 'import datetime; print((datetime.date.today() - datetime.timedelta(days=7)).isoformat())' 2>/dev/null ||
  echo "")

awk -F'\t' -v total="$TOTAL" -v color="$COLOR" -v cutoff="$CUTOFF" -v main="$DEFAULT_BRANCH" '
  function bold(s){ return color? "\033[1m" s "\033[0m" : s }
  function col(rate){ if(!color) return ""; if(rate>=30) return "\033[31m"; if(rate>=15) return "\033[33m"; return "\033[2m" }
  function off(){ return color? "\033[0m" : "" }
  function bar(rate,  n,i,s){ n=int(rate/10+0.5); s=""; for(i=0;i<10;i++) s=s (i<n?"█":"░"); return s }
  function fmtdate(d,  b){ split(d,b,"-"); return b[1] "-" b[2] "-" b[3] }
  function seencol(d){ if(!color||cutoff=="") return ""; return (d>=cutoff)? "\033[31m" : "\033[32m" }
  BEGIN { sec=-1; curfile="" }
  {
    flag=$1; file=$3; count=$4; nbranch=$5; onmain=$6; disp=$7
    rate=(count/total)*100
    split($9,ds,"T"); dpart=ds[1]
    if (flag!=sec) { sec=flag; curfile=""
      print ""
      print bold(flag==1 ? "▌ LIKELY FLAKY  (failed on ≥2 branches)" \
                         : "▌ SINGLE-BRANCH FAILURES  (likely real PR breaks)") }
    if (file!=curfile) { curfile=file; print ""; print "  " file }
    sep=index(disp,"::"); path=(sep?substr(disp,sep+2):disp)
    mainflag=(onmain=="1" ? (color?"\033[31m":"") "⚑" main off() "  " : "")
    seen=(dpart!="" ? seencol(dpart) "(last seen " fmtdate(dpart) ")" off() "  " : "")
    if (flag==1)   # LIKELY FLAKY: show rate bar + %
      printf "    %s%s %.0f%% (%d/%d)%s  %db  %s%s%s\n",
        col(rate), bar(rate), rate, count, total, off(), nbranch, mainflag, seen, path
    else           # SINGLE-BRANCH: rate is misleading, omit it
      printf "    %s%s%s\n", mainflag, seen, path
  }' "$RECORDS"

rm -f "$RECORDS"
