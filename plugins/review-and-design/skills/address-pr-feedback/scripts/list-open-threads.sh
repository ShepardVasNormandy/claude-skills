#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: list-open-threads.sh [-R owner/repo] [<pr>]

Prints the unresolved review threads of a GitHub pull request as a JSON array.

  <pr>            PR number or URL. Defaults to the PR of the current branch.
  -R owner/repo   Repository. Defaults to the repository of the current directory,
                  or the one in the PR URL.
  -h, --help      Show this help.

Each element:
  {"id", "path", "line", "isOutdated", "author", "body", "url",
   "comments": [{"author", "body", "createdAt"}]}

"author" and "body" come from the first comment of the thread. "comments" holds
the whole thread in order. "line" is null when GitHub can no longer place the
comment on the current diff.

Requires gh (authenticated) and jq.
EOF
}

repo=""
pr=""
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help) usage; exit 0 ;;
    -R | --repo)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      repo=$2; shift 2 ;;
    -*) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$pr" ] || { echo "error: only one PR argument is allowed" >&2; exit 2; }
      pr=$1; shift ;;
  esac
done

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed" >&2; exit 1; }
done

case $pr in
  https://*/pull/*)
    path=${pr#https://*/}
    url_repo=$(printf '%s' "$path" | cut -d/ -f1-2)
    pr=$(printf '%s' "$path" | cut -d/ -f4)
    [ -n "$repo" ] || repo=$url_repo
    ;;
esac

if [ -z "$pr" ]; then
  pr=$(gh pr view --json number --jq .number) || { echo "error: no PR found for the current branch" >&2; exit 1; }
fi
case $pr in
  '' | *[!0-9]*) echo "error: PR must be a number or a pull request URL, got '$pr'" >&2; exit 2 ;;
esac

if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi
owner=${repo%%/*}
name=${repo#*/}

# shellcheck disable=SC2016 # $vars below are GraphQL variables
query='
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 100) {
            nodes { author { login } body url createdAt }
          }
        }
      }
    }
  }
}'

all='[]'
after=""
while :; do
  if [ -n "$after" ]; then
    page=$(gh api graphql -f query="$query" -f owner="$owner" -f name="$name" -F number="$pr" -f after="$after")
  else
    page=$(gh api graphql -f query="$query" -f owner="$owner" -f name="$name" -F number="$pr")
  fi
  threads=$(printf '%s' "$page" | jq '.data.repository.pullRequest.reviewThreads')
  if [ "$threads" = null ]; then
    echo "error: PR #$pr not found in $repo" >&2
    exit 1
  fi
  all=$(jq -n --argjson a "$all" --argjson b "$(printf '%s' "$threads" | jq '.nodes')" '$a + $b')
  [ "$(printf '%s' "$threads" | jq -r '.pageInfo.hasNextPage')" = true ] || break
  after=$(printf '%s' "$threads" | jq -r '.pageInfo.endCursor')
done

printf '%s' "$all" | jq '[
  .[] | select(.isResolved | not) | {
    id,
    path,
    line,
    isOutdated,
    author: (.comments.nodes[0].author.login // "ghost"),
    body: (.comments.nodes[0].body // ""),
    url: (.comments.nodes[0].url // null),
    comments: [.comments.nodes[] | {author: (.author.login // "ghost"), body, createdAt}]
  }
]'
