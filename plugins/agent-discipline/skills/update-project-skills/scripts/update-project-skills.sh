#!/usr/bin/env bash
# Usage: update-project-skills.sh [marketplace]   (default: claude-skills)
# Updates the marketplace and every installed plugin from it, then prints which skills were
# added, modified or removed. CLAUDE_CONFIG_DIR overrides ~/.claude.
set -euo pipefail

MARKETPLACE=${1:-claude-skills}
DEFAULT_REPO="ShepardVasNormandy/claude-skills"

command -v claude >/dev/null 2>&1 || { echo "claude CLI not found on PATH."; exit 1; }

installed_field() {
  claude plugin list --json 2>/dev/null | awk -v id="$1@$MARKETPLACE" -v f="$2" '
    $0 ~ /^    "id": / { cur = ($0 == "    \"id\": \"" id "\",") }
    cur && !done && index($0, "    \"" f "\": \"") == 1 { v = $0; sub(/^[^:]*: "/, "", v); sub(/",?$/, "", v); print v; done = 1 }'
}

# The CLI sometimes returns before the new version is extracted to the cache.
wait_for_skills() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -d "$1" ] && return 0
    sleep 0.5
  done
  [ -d "$1" ]
}

report_skill_changes() {
  local before_skills=$1 after_skills=$2 out
  if [ ! -d "$before_skills" ]; then
    ls -1 "$after_skills" 2>/dev/null | sed 's/^/    + /'
    return 0
  fi
  out=$(diff -rq "$before_skills" "$after_skills" 2>/dev/null || true)
  printf '%s\n' "$out" | awk -v b="$before_skills" -v a="$after_skills" '
    function skill(path, root) { path = substr(path, length(root) + 2); sub(/[\/:].*/, "", path); return path }
    index($0, "Only in " a ": ") == 1 { print "1 + " substr($0, length("Only in " a ": ") + 1); next }
    index($0, "Only in " b ": ") == 1 { print "3 - " substr($0, length("Only in " b ": ") + 1); next }
    index($0, "Only in " a "/") == 1 { print "2 ~ " skill(substr($0, 9), a); next }
    index($0, "Only in " b "/") == 1 { print "2 ~ " skill(substr($0, 9), b); next }
    index($0, "Files " b "/") == 1 { print "2 ~ " skill(substr($0, 7), b) }
  ' | sort -u | sed 's/^[0-9] /    /'
}

if ! claude plugin marketplace list --json 2>/dev/null | grep -xF "    \"name\": \"$MARKETPLACE\"," >/dev/null; then
  if [ "$MARKETPLACE" = claude-skills ]; then
    echo "Marketplace $MARKETPLACE is not installed. Add it with: claude plugin marketplace add $DEFAULT_REPO"
  else
    echo "Marketplace $MARKETPLACE is not installed. Add it with: claude plugin marketplace add <owner/repo>"
  fi
  exit 1
fi

PLUGINS=$(claude plugin list --json 2>/dev/null | awk -v m="@$MARKETPLACE" '
  $0 ~ /^    "id": "/ {
    id = $0; sub(/^    "id": "/, "", id); sub(/",?$/, "", id)
    if (length(id) > length(m) && substr(id, length(id) - length(m) + 1) == m) print substr(id, 1, length(id) - length(m))
  }' | sort -u)

if [ -z "$PLUGINS" ]; then
  echo "No plugin from $MARKETPLACE is installed. Install one with: claude plugin install <plugin>@$MARKETPLACE"
  exit 0
fi

echo "==> Updating marketplace '$MARKETPLACE'"
claude plugin marketplace update "$MARKETPLACE"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
CHANGED=""
FAILED=0

for plugin in $PLUGINS; do
  before_path=$(installed_field "$plugin" installPath)
  before=${before_path##*/}
  if [ -n "$before_path" ] && [ -d "$before_path/skills" ]; then
    mkdir -p "$work/$plugin"
    cp -R "$before_path/skills" "$work/$plugin/skills"
  fi

  echo "==> Updating $plugin@$MARKETPLACE (current: ${before:-unknown})"
  if ! claude plugin update "$plugin@$MARKETPLACE"; then
    echo "    update failed"
    FAILED=1
    continue
  fi
  after_path=$(installed_field "$plugin" installPath)
  after=${after_path##*/}
  if [ -z "$after_path" ] || ! wait_for_skills "$after_path/skills"; then
    echo "    no skills found in the cache after the update"
    continue
  fi

  changes=$(report_skill_changes "$work/$plugin/skills" "$after_path/skills")
  if [ -z "$changes" ]; then
    echo "    already up to date (${after})"
    continue
  fi
  CHANGED="$CHANGED$plugin@$MARKETPLACE  (${before:-none} -> $after)
$changes

"
done

echo
echo "================ Skill changes ================"
if [ -z "$CHANGED" ]; then
  echo "No skill changed. Every $MARKETPLACE plugin that updated is up to date."
  exit "$FAILED"
fi

printf '%s' "$CHANGED"
echo "Legend: + added   ~ modified   - removed"
echo "Restart Claude Code for the updates to take effect."
exit "$FAILED"
