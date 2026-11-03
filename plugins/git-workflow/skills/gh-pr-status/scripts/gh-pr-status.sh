#!/usr/bin/env bash
# Formatted status of "what to check on GitHub": your open PRs (CI + unresolved
# review threads) and PRs where you're a reviewer (TO_REVIEW / REVIEWED / AUTHOR_REPLIED).
# Stacked PRs (base branch is another PR's head branch in the same list) are printed
# indented under their parent instead of flat, so a stack reads as a tree.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gh-pr-status.sh [--mine] [--other]

Prints what to check on GitHub for the repo in the current directory:
  --mine   only "YOUR OPEN PRs" (CI, review decision, resolved/total review threads)
  --other  only "PRs AWAITING YOUR REVIEW" (TO_REVIEW / AUTHOR_REPLIED)
With neither flag, prints both sections. Stacked PRs print as an indented tree.
Requires gh (authenticated) and jq.
EOF
}

# --mine: only "YOUR OPEN PRs". --other: only "PRs AWAITING YOUR REVIEW". Neither: both.
ONLY_MINE=0
ONLY_OTHER=0
for arg in "$@"; do
  case "$arg" in
    --mine) ONLY_MINE=1 ;;
    --other) ONLY_OTHER=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
if [ "$ONLY_MINE" = "1" ] && [ "$ONLY_OTHER" = "0" ]; then
  SHOW_MINE=1; SHOW_OTHER=0
elif [ "$ONLY_OTHER" = "1" ] && [ "$ONLY_MINE" = "0" ]; then
  SHOW_MINE=0; SHOW_OTHER=1
else
  SHOW_MINE=1; SHOW_OTHER=1
fi

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""
fi

OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
ME=$(gh api user --jq '.login')

THREADS_QUERY='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 50) { nodes { author { login } } }
        }
      }
    }
  }
}'

# Enriches a PR array with .depth (hops to the trunk within this same list) and
# .rootNumber (the PR number at the bottom of its chain), then sorts so each
# stack's members print consecutively, root first.
JQ_ENRICH_SORT='
def depth($map):
  if $map[.baseRefName] then 1 + ($map[.baseRefName] | depth($map)) else 0 end;
def rootnum($map):
  if $map[.baseRefName] then ($map[.baseRefName] | rootnum($map)) else .number end;
. as $items
| ($items | INDEX(.headRefName)) as $map
| [ $items[] | . + {
    depth: depth($map),
    rootNumber: rootnum($map),
    parentNumber: ($map[.baseRefName].number // null)
  } ]
| sort_by(-.rootNumber, .depth)
'

review_threads() {
  gh api graphql -f query="$THREADS_QUERY" -F owner="$OWNER" -F repo="$REPO" -F number="$1" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes'
}

unresolved_count() {
  echo "$1" | jq '[.[] | select(.isResolved == false)] | length'
}

author_replied() {
  echo "$1" | jq --arg me "$ME" '
    [.[] | select(
      (.isResolved == false) and
      (.comments.nodes | any(.author.login == $me)) and
      (.comments.nodes[-1].author.login != $me)
    )] | length > 0'
}

ci_status() {
  echo "$1" | jq -r '
    (. // []) as $checks |
    if ($checks | length) == 0 then "NONE"
    elif ($checks | map(select(.__typename == "CheckRun" and .status != "COMPLETED")) | length) > 0 then "PENDING"
    elif ($checks | map(select(.__typename == "StatusContext" and (.state == "PENDING" or .state == "EXPECTED"))) | length) > 0 then "PENDING"
    elif ($checks | map(select(
        (.__typename == "CheckRun" and (.conclusion == "FAILURE" or .conclusion == "CANCELLED" or .conclusion == "TIMED_OUT" or .conclusion == "ACTION_REQUIRED"))
        or (.__typename == "StatusContext" and .state == "FAILURE")
      )) | length) > 0 then "FAIL"
    else "PASS"
    end'
}

ci_label() {
  case "$1" in
    PASS) printf '%spass%s' "$GREEN" "$RESET" ;;
    FAIL) printf '%sfail%s' "$RED" "$RESET" ;;
    PENDING) printf '%srun %s' "$YELLOW" "$RESET" ;;
    *) printf '%snone%s' "$DIM" "$RESET" ;;
  esac
}

review_label() {
  case "$1" in
    APPROVED) printf '%sapproved%s' "$GREEN" "$RESET" ;;
    CHANGES_REQUESTED) printf '%schanges req.%s' "$RED" "$RESET" ;;
    REVIEW_REQUIRED) printf '%spending%s' "$YELLOW" "$RESET" ;;
    *) printf '%sno review%s' "$DIM" "$RESET" ;;
  esac
}

review_status_label() {
  case "$1" in
    TO_REVIEW) printf '%sTO_REVIEW%s' "$YELLOW" "$RESET" ;;
    AUTHOR_REPLIED) printf '%sAUTHOR_REPLIED%s' "$CYAN" "$RESET" ;;
    *) printf '%sREVIEWED%s' "$DIM" "$RESET" ;;
  esac
}

indent_of() { printf '%*s' "$(( $1 * 2 ))" ""; }

echo "${BOLD}GitHub PR check — $OWNER/$REPO — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo

if [ "$SHOW_MINE" = "1" ]; then
# ---- Section 1: my open PRs ----
MY_PRS=$(gh pr list --author "@me" --state open \
  --json number,title,url,headRefName,baseRefName,statusCheckRollup,reviewDecision)
MY_SORTED=$(echo "$MY_PRS" | jq -c "$JQ_ENRICH_SORT" | jq -c '.[]')

echo "${BOLD}== YOUR OPEN PRs ==${RESET}"
if [ -z "$MY_SORTED" ]; then
  echo "(none)"
else
  first=1
  while IFS= read -r pr; do
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r 'if (.title|length) > 68 then .title[0:67] + "…" else .title end')
    url=$(echo "$pr" | jq -r '.url')
    depth=$(echo "$pr" | jq -r '.depth')
    parent=$(echo "$pr" | jq -r '.parentNumber // "null"')
    review_decision=$(echo "$pr" | jq -r '.reviewDecision // "NONE"')
    checks=$(echo "$pr" | jq -c '.statusCheckRollup')

    if [ "$depth" = "0" ]; then
      [ "$first" != "1" ] && echo
      first=0
    fi

    status=$(ci_status "$checks")
    threads=$(review_threads "$number")
    unresolved=$(unresolved_count "$threads")
    total=$(echo "$threads" | jq 'length')
    resolved=$((total - unresolved))
    threads_disp="$resolved/$total"
    [ "$unresolved" != "0" ] && threads_disp="${YELLOW}${resolved}${RESET}/${total}"

    indent=$(indent_of "$depth")
    prefix="$indent"; [ "$depth" != "0" ] && prefix="${indent}└ "
    cont="$indent"; [ "$depth" != "0" ] && cont="${indent}  "

    printf '%s%s#%-5s%s %s\n' "$prefix" "$BOLD" "$number" "$RESET" "$title"
    parent_note=""
    [ "$parent" != "null" ] && parent_note="  ${DIM}on #${parent}${RESET}"
    printf '%s  ci:%s  review:%s  threads:%s%s  %s%s%s\n' \
      "$cont" "$(ci_label "$status")" "$(review_label "$review_decision")" \
      "$threads_disp" "$parent_note" "$DIM" "$url" "$RESET"
  done <<< "$MY_SORTED"
fi
fi

if [ "$SHOW_OTHER" = "1" ]; then
[ "$SHOW_MINE" = "1" ] && echo
echo "${BOLD}== PRs AWAITING YOUR REVIEW ==${RESET}"

REQUESTED=$(gh pr list --search "review-requested:@me" --state open \
  --json number,title,url,author,headRefName,baseRefName)
REVIEWED_BY_ME=$(gh pr list --search "reviewed-by:@me" --state open \
  --json number,title,url,author,headRefName,baseRefName)

REVIEW_PRS=$(jq -s --arg me "$ME" \
  '.[0] + .[1] | unique_by(.number) | map(select(.author.login != $me))' \
  <(echo "$REQUESTED") <(echo "$REVIEWED_BY_ME"))
REQUESTED_NUMBERS=$(echo "$REQUESTED" | jq -r '.[].number')
REVIEW_SORTED=$(echo "$REVIEW_PRS" | jq -c "$JQ_ENRICH_SORT" | jq -c '.[]')

if [ -z "$REVIEW_SORTED" ]; then
  echo "(none)"
else
  first=1
  while IFS= read -r pr; do
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r 'if (.title|length) > 58 then .title[0:57] + "…" else .title end')
    url=$(echo "$pr" | jq -r '.url')
    author=$(echo "$pr" | jq -r '.author.login')
    depth=$(echo "$pr" | jq -r '.depth')
    parent=$(echo "$pr" | jq -r '.parentNumber // "null"')

    threads=$(review_threads "$number")
    replied=$(author_replied "$threads")

    if [ "$replied" = "true" ]; then
      review_status="AUTHOR_REPLIED"
    elif echo "$REQUESTED_NUMBERS" | grep -qx "$number"; then
      review_status="TO_REVIEW"
    else
      review_status="REVIEWED"
    fi

    # Already reviewed and not re-requested or replied to: nothing to act on, skip it.
    [ "$review_status" = "REVIEWED" ] && continue

    if [ "$depth" = "0" ]; then
      [ "$first" != "1" ] && echo
      first=0
    fi

    unresolved=$(unresolved_count "$threads")
    total=$(echo "$threads" | jq 'length')
    resolved=$((total - unresolved))
    threads_disp="$resolved/$total"
    [ "$unresolved" != "0" ] && threads_disp="${YELLOW}${resolved}${RESET}/${total}"

    indent=$(indent_of "$depth")
    prefix="$indent"; [ "$depth" != "0" ] && prefix="${indent}└ "
    cont="$indent"; [ "$depth" != "0" ] && cont="${indent}  "

    printf '%s%s#%-5s%s %s  %sby %s%s\n' "$prefix" "$BOLD" "$number" "$RESET" "$title" "$DIM" "$author" "$RESET"
    parent_note=""
    [ "$parent" != "null" ] && parent_note="  ${DIM}on #${parent}${RESET}"
    printf '%s  status:%s  threads:%s%s  %s%s%s\n' \
      "$cont" "$(review_status_label "$review_status")" "$threads_disp" "$parent_note" "$DIM" "$url" "$RESET"
  done <<< "$REVIEW_SORTED"
fi
fi
