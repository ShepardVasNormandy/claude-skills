#!/usr/bin/env bash
# Runs update-project-skills.sh against a stub `claude` and a fake CLAUDE_CONFIG_DIR.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../skills/update-project-skills/scripts/update-project-skills.sh"
failures=0

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/bin"
cat > "$scratch/bin/claude" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cache="$CLAUDE_CONFIG_DIR/plugins/cache/claude-skills/agent-discipline"
active=1.2.0
[ -d "$cache/1.10.0" ] && active=1.10.0
case "$*" in
  "plugin marketplace list --json")
    printf '[\n  {\n    "name": "claude-plugins-official",\n    "source": "github"\n  }'
    if [ "${STUB_MARKETPLACE:-}" = yes ]; then
      printf ',\n  {\n    "name": "claude-skills",\n    "source": "github"\n  }'
    fi
    printf '\n]\n'
    ;;
  "plugin marketplace list")
    printf 'Configured marketplaces:\n\n'
    printf '  \xe2\x9d\xaf claude-plugins-official\n    Source: GitHub (anthropics/claude-plugins-official)\n'
    if [ "${STUB_MARKETPLACE:-}" = notadded ]; then
      printf '\n  \xe2\x9d\xaf claude-skills\n    Source: claude.ai (not added)\n'
    fi
    ;;
  "plugin list --json")
    printf '[\n'
    if [ "${STUB_MARKETPLACE:-}" = yes ]; then
      for scope in user local; do
        printf '  {\n    "id": "agent-discipline@claude-skills",\n    "version": "%s",\n    "scope": "%s",\n    "installPath": "%s/%s"\n  },\n' \
          "$active" "$scope" "$cache" "$active"
      done
    fi
    printf '  {\n    "id": "other@claude-skills-extra",\n    "version": "1.0.0",\n    "scope": "user",\n    "installPath": "/nowhere"\n  }\n]\n'
    ;;
  "plugin marketplace update claude-skills") echo "updated marketplace" ;;
  "plugin update agent-discipline@claude-skills")
    if [ "${STUB_UPDATE_FAILS:-}" = yes ]; then
      echo "update exploded" >&2
      exit 1
    fi
    cp -R "$cache/1.2.0" "$cache/1.10.0"
    mkdir -p "$cache/1.10.0/skills/new-skill"
    echo new > "$cache/1.10.0/skills/new-skill/SKILL.md"
    echo changed > "$cache/1.10.0/skills/changed-skill/SKILL.md"
    ;;
  *) echo "stub claude: unexpected: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$scratch/bin/claude"

check() {
  local desc=$1 want=$2 code=$3 out=$4
  shift 4
  local ok=1 needle
  [ "$code" -eq "$want" ] || ok=0
  for needle in "$@"; do
    printf '%s\n' "$out" | grep -qF -- "$needle" || ok=0
  done
  if [ "$ok" = 1 ]; then
    printf 'ok - %s\n' "$desc"
  else
    printf 'not ok - %s (exit %s)\n%s\n' "$desc" "$code" "$out" | sed '2,$s/^/    /'
    failures=$((failures + 1))
  fi
}

seed_cache() {
  local cache=$1 v
  for v in 1.0.0 1.2.0; do
    mkdir -p "$cache/$v/skills/changed-skill" "$cache/$v/skills/same-skill"
    echo "$v" > "$cache/$v/skills/changed-skill/SKILL.md"
    echo same > "$cache/$v/skills/same-skill/SKILL.md"
  done
}

config="$scratch/absent"
mkdir -p "$config"
code=0
out=$(PATH="$scratch/bin:$PATH" CLAUDE_CONFIG_DIR="$config" bash "$script" 2>&1) || code=$?
check "marketplace not installed" 1 "$code" "$out" "is not installed" \
  "claude plugin marketplace add ShepardVasNormandy/claude-skills"

code=0
out=$(PATH="$scratch/bin:$PATH" CLAUDE_CONFIG_DIR="$config" STUB_MARKETPLACE=notadded bash "$script" 2>&1) || code=$?
check "ignores a claude.ai entry that is not added" 1 "$code" "$out" "is not installed"

config="$scratch/installed"
seed_cache "$config/plugins/cache/claude-skills/agent-discipline"
code=0
out=$(PATH="$scratch/bin:$PATH" CLAUDE_CONFIG_DIR="$config" STUB_MARKETPLACE=yes bash "$script" 2>&1) || code=$?
check "diffs the active version before and after" 0 "$code" "$out" \
  "(1.2.0 -> 1.10.0)" "+ new-skill" "~ changed-skill"
if printf '%s\n' "$out" | grep -qF "same-skill"; then
  check "leaves unchanged skills out" 0 1 "$out"
fi
if [ "$(printf '%s\n' "$out" | grep -cF 'agent-discipline@claude-skills  (')" -ne 1 ]; then
  check "reports a plugin listed in two scopes once" 0 1 "$out"
fi

config="$scratch/failing"
seed_cache "$config/plugins/cache/claude-skills/agent-discipline"
code=0
out=$(PATH="$scratch/bin:$PATH" CLAUDE_CONFIG_DIR="$config" STUB_MARKETPLACE=yes STUB_UPDATE_FAILS=yes bash "$script" 2>&1) || code=$?
check "a failed update is reported and exits non-zero" 1 "$code" "$out" \
  "    update failed" "Skill changes"

[ "$failures" -eq 0 ]
