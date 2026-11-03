#!/usr/bin/env bash
# Usage: scripts/validate.sh [root]. Prints path: reason per problem; exit 1 if any.
set -euo pipefail
export LC_ALL=C

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root"
problems=0

report() {
  printf '%s: %s\n' "$1" "$2"
  problems=$((problems + 1))
}

list_files() {
  local f pat
  {
    if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
      git ls-files -z --cached --others --exclude-standard
    else
      find . \( -path ./.git -o -path ./docs/superpowers -o -path ./tests/fixtures -o -name node_modules \) -prune \
        -o -type f -print0
    fi
  } | while IFS= read -r -d '' f; do
    f=${f#./}
    case $f in
      tests/fixtures/* | docs/superpowers/* | node_modules/* | */node_modules/*) continue ;;
    esac
    [ -f "$f" ] || continue
    for pat in "$@"; do
      # shellcheck disable=SC2254 # $pat is a glob on purpose
      case $f in
        $pat) printf '%s\n' "$f"; break ;;
      esac
    done
  done
}

while IFS= read -r f; do
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f" 2>/dev/null ||
    report "$f" "invalid JSON"
done < <(list_files '*.json')

manifest_check=$(cat <<'JS'
const fs = require('fs');
const owner = 'ShepardVasNormandy';
const repository = 'https://github.com/ShepardVasNormandy/claude-skills';
const out = [];
const read = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return undefined; } };
const dirs = fs.existsSync('plugins')
  ? fs.readdirSync('plugins', { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
  : [];

const mp = '.claude-plugin/marketplace.json';
if (!fs.existsSync(mp)) {
  out.push(`${mp}: missing`);
} else {
  const m = read(mp);
  if (m) {
    if (m.name !== 'claude-skills') out.push(`${mp}: name must be "claude-skills"`);
    if (!m.owner || m.owner.name !== owner) out.push(`${mp}: owner.name must be "${owner}"`);
    const listed = Array.isArray(m.plugins) ? m.plugins : [];
    if (!Array.isArray(m.plugins)) out.push(`${mp}: plugins must be an array`);
    const names = listed.map((p) => p && p.name);
    for (const p of listed) {
      const name = p && p.name;
      if (!dirs.includes(name)) out.push(`${mp}: plugin "${name}" has no plugins/${name} directory`);
      if (names.indexOf(name) !== names.lastIndexOf(name)) out.push(`${mp}: plugin "${name}" listed more than once`);
      if (!p || p.source !== `./plugins/${name}`) out.push(`${mp}: plugin "${name}" source must be "./plugins/${name}"`);
      if (!p || typeof p.description !== 'string' || !p.description) out.push(`${mp}: plugin "${name}" needs a description`);
    }
    for (const d of dirs) if (!names.includes(d)) out.push(`${mp}: plugins/${d} is not listed`);
  }
}

for (const d of dirs) {
  const pj = `plugins/${d}/.claude-plugin/plugin.json`;
  if (!fs.existsSync(pj)) { out.push(`${pj}: missing`); continue; }
  const p = read(pj);
  if (!p) continue;
  if (p.name !== d) out.push(`${pj}: name must be "${d}"`);
  if (typeof p.version !== 'string' || !/^\d+\.\d+\.\d+$/.test(p.version)) out.push(`${pj}: version must be semver like "1.0.0"`);
  if (typeof p.description !== 'string' || !p.description) out.push(`${pj}: description missing`);
  if (!p.author || p.author.name !== owner) out.push(`${pj}: author.name must be "${owner}"`);
  if (p.license !== 'MIT') out.push(`${pj}: license must be "MIT"`);
  if (p.repository !== repository) out.push(`${pj}: repository must be "${repository}"`);
}

if (out.length) console.log(out.join('\n'));
JS
)
manifest_problems=$(node -e "$manifest_check")
if [ -n "$manifest_problems" ]; then
  printf '%s\n' "$manifest_problems"
  problems=$((problems + $(printf '%s\n' "$manifest_problems" | wc -l)))
fi

for d in plugins/*/skills/*/; do
  [ -d "$d" ] || continue
  [ -f "${d}SKILL.md" ] || report "${d%/}" "skill directory has no SKILL.md"
done

for f in plugins/*/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir=$(basename "$(dirname "$f")")
  name="" desc="" has_desc=0 fm_error=""
  while IFS=$'\t' read -r key val; do
    case $key in
      error) fm_error=$val ;;
      name) name=$val ;;
      description) desc=$val ;;
      hasdesc) has_desc=$val ;;
    esac
  done < <(awk -v q="'" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[ \t]*$/) { print "error\tmissing front matter"; bad = 1; exit } next }
    /^---[ \t]*$/ { closed = 1; exit }
    /^[A-Za-z0-9_-]+:/ {
      key = $0; sub(/:.*/, "", key)
      val = $0; sub(/^[^:]*:[ \t]*/, "", val); sub(/[ \t]+$/, "", val)
      if (val ~ /^[>|][+-]?$/) val = ""
      v[key] = val; cur = key; next
    }
    /^[ \t]/ && cur != "" {
      line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
      v[cur] = (v[cur] == "" ? line : v[cur] " " line); next
    }
    END {
      if (bad) exit
      if (!closed) { print "error\tunterminated front matter"; exit }
      for (k in v) {
        s = v[k]
        if (s ~ /^".*"$/ || s ~ "^" q ".*" q "$") s = substr(s, 2, length(s) - 2)
        v[k] = s
      }
      print "name\t" v["name"]
      print "description\t" v["description"]
      print "hasdesc\t" (("description" in v) ? 1 : 0)
    }' "$f")
  if [ -n "$fm_error" ]; then
    report "$f" "$fm_error"
    continue
  fi
  [ "$name" = "$dir" ] || report "$f" "front matter name '$name' does not match directory '$dir'"
  # Dropping UTF-8 continuation bytes makes wc count characters.
  dlen=$(printf '%s' "$desc" | tr -d '\200-\277' | wc -c)
  dlen=$((dlen))
  if [ "$has_desc" != 1 ] || [ -z "$desc" ]; then
    report "$f" "front matter description missing"
  elif [ "$dlen" -gt 1024 ]; then
    report "$f" "front matter description is $dlen chars (max 1024)"
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  have_shellcheck=1
else
  have_shellcheck=0
  echo "notice: shellcheck not installed, skipping the shellcheck pass" >&2
fi

while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || report "$f" "bash -n failed"
  if [ "$have_shellcheck" = 1 ]; then
    if ! sc=$(shellcheck -S warning -f gcc "$f" 2>&1); then
      printf '%s\n' "$sc"
      problems=$((problems + 1))
    fi
  fi
  while IFS=: read -r line what; do
    report "$f:$line" "not portable ($what)"
  done < <(
    grep -nE '(^|[^A-Za-z0-9_])date[[:space:]]+(-d|--date)' "$f" | sed 's/:.*/:GNU-only date flag, use date -v or Node/' || true
    grep -nE '(^|[^A-Za-z0-9_])(mapfil[e]|readarra[y])([^A-Za-z0-9_]|$)' "$f" | sed 's/:.*/:bash 4 builtin/' || true
    grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*(,{1,2}|\^{1,2})\}' "$f" | sed 's/:.*/:bash 4 case conversion/' || true
  )
done < <(list_files '*.sh' '.githooks/*')

[ "$problems" -eq 0 ]
