#!/usr/bin/env bash
# Usage: tests/config-contract.sh [root]. Checks every SKILL.md against the Config and Requires contract.
set -euo pipefail
export LC_ALL=C

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root"
problems=0

report() {
  printf '%s: %s\n' "$1" "$2"
  problems=$((problems + 1))
}

# First-column keys of the key table: under "## Config" for a skill, anywhere for a config doc.
table_keys() {
  awk -v section="$1" '
    BEGIN { on = (section == 0) }
    section && /^## Config[ \t]*$/ { on = 1; next }
    section && on && /^#/ { exit }
    on && /^\|/ {
      cell = $0; sub(/^\|[ \t]*/, "", cell); sub(/[ \t]*\|.*$/, "", cell); gsub(/`/, "", cell)
      if (cell == "" || cell == "Key" || cell ~ /^:?-+:?$/) next
      print cell
    }' "$2"
}

for f in plugins/*/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  plugin=${f#plugins/}
  plugin=${plugin%%/*}
  doc="docs/configuration/$plugin.md"

  if grep -qF '.local.md' "$f"; then
    grep -q '^## Config[[:space:]]*$' "$f" || report "$f" "mentions .local.md but has no '## Config' section"
    grep -qF 'Never guess a value' "$f" || report "$f" "mentions .local.md but lacks 'Never guess a value'"
  fi

  if grep -q '^## Config[[:space:]]*$' "$f"; then
    awk '/^## Config[ \t]*$/ { on = 1; next } on && /^#/ { exit } on' "$f" | grep -qF ".claude/$plugin.local.md" ||
      report "$f" "'## Config' must name .claude/$plugin.local.md"
  fi

  while IFS=: read -r line _; do
    report "$f:$line" "Requires: line must contain 'then stop'"
  done < <(grep -n 'Requires:' "$f" | grep -v 'then stop' || true)

  keys=$(table_keys 1 "$f")
  [ -n "$keys" ] || continue
  if [ ! -f "$doc" ]; then
    report "$f" "has config keys but $doc is missing"
    continue
  fi
  documented=$(table_keys 0 "$doc")
  while IFS= read -r key; do
    printf '%s\n' "$documented" | grep -qxF -- "$key" || report "$f" "config key '$key' is not in $doc"
  done <<< "$keys"
done

[ "$problems" -eq 0 ]
