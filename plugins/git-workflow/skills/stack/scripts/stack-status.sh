#!/usr/bin/env bash
# stack-status.sh
# Print the current gh-stack stack with PR number, CI status and review status,
# so the output can be dropped into a Claude conversation as context.
#
# Usage:
#   stack-status.sh            current stack (gh stack view --json)
#   stack-status.sh --no-fetch skip per-PR CI/review enrichment, show structure only
#
# Read-only. Never mutates git, gh stack or GitHub.

set -euo pipefail

FETCH=1

for arg in "$@"; do
  case "$arg" in
    --no-fetch) FETCH=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# --- sanity guards ------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) is not installed."; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Not inside a git repository, nothing to show."; exit 0; }
case "$(gh extension list 2>/dev/null || true)" in
  *github/gh-stack*) ;;
  *) echo "gh-stack extension is not installed. Run: gh extension install github/gh-stack"; exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "jq is required for this script."; exit 0; }

STACK_JSON="$(gh stack view --json 2>&1 || true)"
if ! printf '%s' "$STACK_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "No stack found: $(printf '%s' "$STACK_JSON" | tail -n 1)"
  exit 0
fi

TRUNK="$(printf '%s' "$STACK_JSON" | jq -r '.trunk')"

# Fetch one PR's CI/review data by number (one light query, retried once on a
# transient GitHub hiccup). Echoes a JSON object on success, nothing otherwise.
fetch_pr_details() {
  local number="$1" out
  for _ in 1 2; do
    out="$(gh pr view "$number" \
            --json number,reviewDecision,state,isDraft,statusCheckRollup,reviews,author \
            2>/dev/null || true)"
    if printf '%s' "$out" | jq -e 'type == "object"' >/dev/null 2>&1; then
      printf '%s' "$out"; return 0
    fi
  done
  return 0
}

# Reduce one PR JSON object to "number|ci|review".
reduce_pr() {
  jq -r '
    [
      (.number),
      ( [.statusCheckRollup[]? | (.conclusion // .state // "")]
        | if   any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT") then "fail"
          elif any(. == "" or . == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED" or . == "WAITING") then "run"
          elif any(. == "SUCCESS") then "pass"
          elif length > 0 then "pass"   # only CANCELLED/SKIPPED/NEUTRAL left
          else "none" end ),
      ( if   .state == "MERGED"            then "merged"
        elif .state == "CLOSED"            then "closed"
        elif .isDraft                      then "draft"
        elif .reviewDecision == "APPROVED" then "approved"
        elif .reviewDecision == "CHANGES_REQUESTED" then "changes requested"
        else "needs approvals" end )
    ] | join("|")
  '
}

# Emit one line per human reviewer who actually submitted a review:
# "login<TAB>STATE" (latest review per reviewer). Skips the PR author and bots,
# so we can tell apart "nobody looked yet" from "reviewed, awaiting re-review".
review_activity() {
  jq -r '
    (.author.login) as $author
    | [ .reviews[]?
        | select(.author.login != $author)
        | select((.author.login | ascii_downcase) | endswith("[bot]") or . == "coderabbitai" | not)
      ]
    | group_by(.author.login)
    | map(.[-1] | [ .author.login, .state ] | @tsv)
    | .[]
  '
}

# Emit one line per FAILED check: "name<TAB>detailsUrl".
# Reads the same PR JSON, so no extra GitHub call.
failing_checks() {
  jq -r '
    .statusCheckRollup[]?
    | select((.conclusion // .state // "") as $c
             | $c == "FAILURE" or $c == "ERROR" or $c == "TIMED_OUT")
    | [ (.name // .context // "check"), (.detailsUrl // .targetUrl // "") ]
    | @tsv
  '
}

ci_badge() {
  case "$1" in
    fail) printf '\xe2\x9c\x97 checks failed' ;;   # ✗
    run)  printf '\xe2\x97\x8f checks running' ;;  # ●
    pass) printf '\xe2\x9c\x93 checks passed' ;;   # ✓
    none) printf '\xe2\x80\x93 no checks' ;;       # –
    *)    printf '' ;;
  esac
}

# --- render -------------------------------------------------------------------
echo "Stack (top = tip, bottom = trunk)"
echo
echo "  $TRUNK (trunk)"

# top to bottom: reverse the (bottom-to-top) branches array from gh stack.
while IFS=$'\t' read -r name is_current is_merged is_queued needs_rebase pr_number; do
  [ -z "$name" ] && continue

  marker="  "; [ "$is_current" = "true" ] && marker="> "

  annot=""
  [ "$is_merged" = "true" ] && annot="$annot (merged)"
  [ "$is_queued" = "true" ] && annot="$annot (queued)"
  [ "$needs_rebase" = "true" ] && annot="$annot (needs rebase)"

  if [ -z "$pr_number" ] || [ "$pr_number" = "null" ]; then
    printf '%s(no PR)  %s%s\n' "$marker" "$name" "$annot"
    continue
  fi

  info=""
  pr_json=""
  if [ "$FETCH" -eq 1 ]; then
    pr_json="$(fetch_pr_details "$pr_number")"
    [ -n "$pr_json" ] && info="$(printf '%s' "$pr_json" | reduce_pr || true)"
  fi

  if [ -n "$info" ]; then
    IFS='|' read -r num ci rev <<<"$info"
    printf '%s#%s  [%s] [%s]  %s%s\n' "$marker" "$num" "$rev" "$(ci_badge "$ci")" "$name" "$annot"

    # For open PRs, surface whether a human has actually reviewed yet, and with
    # what verdict, so "needs approvals" doesn't hide "nobody has looked".
    case "$rev" in
      merged|closed|draft) ;;
      *)
        activity=""
        while IFS=$'\t' read -r r_login r_state; do
          [ -z "$r_login" ] && continue
          case "$r_state" in
            APPROVED)          verb="approved" ;;
            CHANGES_REQUESTED) verb="requested changes" ;;
            COMMENTED)         verb="commented" ;;
            DISMISSED)         verb="dismissed" ;;
            *)                 verb="$(printf '%s' "$r_state" | tr '[:upper:]' '[:lower:]')" ;;
          esac
          activity="${activity:+$activity, }$r_login $verb"
        done < <(printf '%s' "$pr_json" | review_activity)

        if [ -n "$activity" ]; then
          printf '      \xe2\x86\xb3 reviewed: %s\n' "$activity"
        else
          printf '      \xe2\x86\xb3 not yet reviewed\n'
        fi ;;
    esac

    # On failure, list the failing jobs and their IDs (parsed from detailsUrl).
    if [ "$ci" = "fail" ]; then
      while IFS=$'\t' read -r job_name job_url; do
        [ -z "$job_name" ] && continue
        job_id="$(printf '%s' "$job_url" | sed -nE 's#.*/job/([0-9]+).*#\1#p')"
        [ -z "$job_id" ] && job_id="$(printf '%s' "$job_url" | sed -nE 's#.*/runs/([0-9]+).*#\1#p')"
        if [ -n "$job_id" ]; then
          printf '      \xe2\x86\xb3 %s  (job %s)\n' "$job_name" "$job_id"
        else
          printf '      \xe2\x86\xb3 %s  %s\n' "$job_name" "$job_url"
        fi
      done < <(printf '%s' "$pr_json" | failing_checks)
    fi
  else
    printf '%s#%s  %s%s\n' "$marker" "$pr_number" "$name" "$annot"
  fi
done < <(printf '%s' "$STACK_JSON" | jq -r '[.branches[]] | reverse | .[] | [.name, .isCurrent, .isMerged, .isQueued, .needsRebase, (.pr.number // "")] | @tsv')

echo
echo "> marks the current branch."
