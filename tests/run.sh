#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fixtures="$root/tests/fixtures"
validate="$root/scripts/validate.sh"
leaks="$root/scripts/check-leaks.sh"
contract="$root/tests/config-contract.sh"
failures=0
out=""

fail() {
  printf 'not ok - %s\n' "$1"
  if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/    /'; fi
  failures=$((failures + 1))
}

# expect <exit code> <description> <text the output must contain, or ""> <command...>
expect() {
  local want=$1 desc=$2 needle=$3 code=0
  shift 3
  out=$("$@" 2>&1) || code=$?
  if [ "$code" -ne "$want" ]; then
    fail "$desc (exit $code, want $want)"
  elif [ -n "$needle" ] && ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
    fail "$desc (output lacks '$needle')"
  else
    printf 'ok - %s\n' "$desc"
  fi
}

expect 0 "validate passes good-plugin" "" "$validate" "$fixtures/good-plugin"
expect 1 "validate rejects bad-name" "name" "$validate" "$fixtures/bad-name"
expect 1 "validate rejects gnu-date" "date" "$validate" "$fixtures/gnu-date"
expect 0 "validate counts description characters, not bytes" "" "$validate" "$fixtures/desc-utf8"
expect 1 "validate rejects a 1025-character description" "1025 chars" "$validate" "$fixtures/desc-long"
expect 0 "validate reads CRLF front matter" "" "$validate" "$fixtures/crlf"

expect 0 "check-leaks passes good-plugin" "" "$leaks" "$fixtures/good-plugin"
expect 1 "check-leaks rejects leak" "[company]" "$leaks" "$fixtures/leak"
expect 1 "check-leaks rejects notion-id" "[notion-id]" "$leaks" "$fixtures/notion-id"
expect 1 "check-leaks rejects slack-id" "[slack-id]" "$leaks" "$fixtures/slack-id"
expect 0 "check-leaks ignores phrases nobody configured" "" "$leaks" "$fixtures/phrase"
expect 1 "check-leaks reads phrases from LEAK_PHRASES" "[phrase]" env LEAK_PHRASES='ship it friday' "$leaks" "$fixtures/phrase"
expect 1 "check-leaks flags a term that collides with a library name" "[company]" env LEAK_TERMS=falcon "$leaks" "$fixtures/allow-mask"
expect 0 "check-leaks masks LEAK_ALLOW matches" "" env LEAK_TERMS=falcon LEAK_ALLOW='falcon-(cli|sdk)' "$leaks" "$fixtures/allow-mask"
expect 1 "check-leaks still catches a colliding term next to an allowed match" "[company]" env LEAK_TERMS=falcon LEAK_ALLOW='falcon-(cli|sdk)' "$leaks" "$fixtures/allow-mixed"
expect 1 "check-leaks rejects a dashed Notion id" "[notion-id]" "$leaks" "$fixtures/notion-uuid"
expect 0 "check-leaks allows placeholder UUIDs" "" "$leaks" "$fixtures/uuid-placeholder"
expect 1 "check-leaks rejects the company in a file name" ":0: [company-path]" "$leaks" "$fixtures/company-path"
expect 1 "check-leaks rejects a teammate name in a file name" "[name-path]" "$leaks" "$fixtures/name-path"
for d in "$fixtures"/camel-company/*/; do
  expect 1 "check-leaks rejects a camelCase company name (camel-company/$(basename "$d"))" "[company]" "$leaks" "$d"
done
expect 1 "check-leaks rejects a configured term followed by digits" "[company]" "$leaks" "$fixtures/ticket-id"
expect 1 "check-leaks finds a Slack id after an uppercase word" "[slack-id]" "$leaks" "$fixtures/slack-after-word"
expect 1 "check-leaks finds W-prefixed Slack ids" "[slack-id]" "$leaks" "$fixtures/slack-prefix"
expect 0 "check-leaks allows uppercase words with digits" "" "$leaks" "$fixtures/slack-benign"
expect 1 "check-leaks rejects a Linear project slug" "[linear-id]" "$leaks" "$fixtures/linear-slug"
expect 1 "check-leaks scans text files with NUL bytes" "[company]" "$leaks" "$fixtures/nul-bytes"
expect 0 "check-leaks skips binary extensions" "" "$leaks" "$fixtures/binary-ext"

scratch=$(mktemp -d)
trap 'chmod -R u+rwx "$scratch"; rm -rf "$scratch"' EXIT

mkdir "$scratch/unreadable"
cp "$fixtures/good-plugin/plugins/demo/skills/demo-skill/SKILL.md" "$scratch/unreadable/"
chmod 000 "$scratch/unreadable/SKILL.md"
expect 2 "check-leaks fails closed when grep errors" "grep failed" "$leaks" "$scratch/unreadable"

mkdir "$scratch/allow-file"
cp "$fixtures/allow-mask/package-notes.md" "$scratch/allow-file/"
printf 'term: falcon\nallow: falcon-(cli|sdk)\n' > "$scratch/allow-file/.leak-terms.local"
expect 0 "check-leaks masks allow: lines from .leak-terms.local" "" "$leaks" "$scratch/allow-file"

repo="$scratch/repo"
cp -R "$fixtures/good-plugin" "$repo"
git -C "$repo" init -q 2>/dev/null
mkdir -p "$repo/ignored"
printf 'ignored/\n' > "$repo/.gitignore"
cp "$fixtures/leak/notes.md" "$repo/ignored/"
cp "$fixtures/gnu-date/plugins/demo/skills/demo-skill/scripts/since.sh" "$repo/ignored/"
expect 0 "check-leaks skips git-ignored files" "" "$leaks" "$repo"
expect 0 "validate skips git-ignored files" "" "$validate" "$repo"

git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init
rm "$repo/plugins/demo/skills/demo-skill/scripts/hello.sh"
cp "$fixtures/leak/notes.md" "$repo/plugins/demo/notes.md"
expect 1 "check-leaks reports leaks when a tracked file was deleted" "[company]" "$leaks" "$repo/plugins/demo"

mkdir "$scratch/extra"
printf 'Ship the Zorblax build, then ping Quillon.\n' > "$scratch/extra/notes.md"
expect 0 "check-leaks ignores terms nobody configured" "" "$leaks" "$scratch/extra"
expect 1 "check-leaks reads terms from LEAK_TERMS" "[company] zorblax" env LEAK_TERMS=zorblax "$leaks" "$scratch/extra"
expect 1 "check-leaks reads names from LEAK_NAMES" "[name] Quillon" env LEAK_NAMES=Quillon "$leaks" "$scratch/extra"

local_repo="$scratch/local-repo"
mkdir "$local_repo"
git -C "$local_repo" init -q 2>/dev/null
cp "$scratch/extra/notes.md" "$local_repo/"
printf '# private\nterm: zorblax\nname: Quillon\n' > "$local_repo/.leak-terms.local"
expect 1 "check-leaks reads terms from .leak-terms.local" "[company] zorblax" "$leaks" "$local_repo"
expect 1 "check-leaks reads names from .leak-terms.local" "[name] Quillon" "$leaks" "$local_repo"

expect 0 "config-contract passes config-ok" "" "$contract" "$fixtures/config-ok"
expect 1 "config-contract rejects config-missing" "## Config" "$contract" "$fixtures/config-missing"
expect 1 "config-contract rejects config-requires" "then stop" "$contract" "$fixtures/config-requires"
expect 1 "config-contract rejects config-undocumented" "channel" "$contract" "$fixtures/config-undocumented"
expect 1 "config-contract rejects another plugin's config file" ".claude/demo.local.md" "$contract" "$fixtures/config-wrong-plugin"

expect 0 "validate passes the repo" "" "$validate" "$root"
expect 0 "check-leaks passes the repo" "" "$leaks" "$root"

# Every other tests/*.sh and plugins/*/tests/*.sh runs with no arguments and must exit 0.
for t in "$root"/tests/*.sh "$root"/plugins/*/tests/*.sh; do
  [ -f "$t" ] || continue
  [ "$t" = "$root/tests/run.sh" ] && continue
  expect 0 "${t#"$root"/}" "" bash "$t"
done

if [ "$failures" -gt 0 ]; then
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
printf 'all checks passed\n'
