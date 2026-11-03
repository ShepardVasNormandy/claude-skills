#!/usr/bin/env bash
# Usage: scripts/check-leaks.sh [root]. Prints path:line: [category] match; exit 1 on any hit, 2 if a search fails.
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")/.." && pwd)
root=${1:-$here}
cd "$root"

# BSD grep has no \b in -E, so word boundaries are spelled out.
b='(^|[^a-z0-9])'
e='([^a-z0-9]|$)'
terms='initech|initrode|vandelay|hooli'
name_list='Jroe|Jane Roe|jroe'

allow=''
phrases=''

# Extra entries come from .leak-terms.local (lines "term: <regex>", "name: <regex>", "phrase: <regex>" or "allow: <regex>") and from LEAK_TERMS / LEAK_NAMES / LEAK_PHRASES (pipe-separated) and LEAK_ALLOW (one regex).
for f in "$here/.leak-terms.local" "$root/.leak-terms.local"; do
  [ -f "$f" ] || continue
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    val=${line#*:}
    val=${val#"${val%%[![:space:]]*}"}
    val=${val%"${val##*[![:space:]]}"}
    [ -n "$val" ] || continue
    case $line in
      term:*) terms="$terms|$val" ;;
      name:*) name_list="$name_list|$val" ;;
      phrase:*) phrases="${phrases:+$phrases|}$val" ;;
      allow:*) allow="$allow$val"$'\n' ;;
    esac
  done < "$f"
done
env_terms=$(printf '%s' "${LEAK_TERMS:-}" | tr -d '\r\n')
env_names=$(printf '%s' "${LEAK_NAMES:-}" | tr -d '\r\n')
env_allow=$(printf '%s' "${LEAK_ALLOW:-}" | tr -d '\r\n')
env_phrases=$(printf '%s' "${LEAK_PHRASES:-}" | tr -d '\r\n')
if [ -n "$env_terms" ]; then terms="$terms|$env_terms"; fi
if [ -n "$env_names" ]; then name_list="$name_list|$env_names"; fi
if [ -n "$env_allow" ]; then allow="$allow$env_allow"$'\n'; fi
if [ -n "$env_phrases" ]; then phrases="${phrases:+$phrases|}$env_phrases"; fi
terms=$(printf '%s' "$terms" | tr 'A-Z' 'a-z')
export LEAK_ALLOW_LIST="$allow"
names="${b}($name_list)${e}"
notion="${b}([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})${e}"
linear='(^|[^a-z0-9-])[a-z][a-z0-9]*(-[a-z][a-z0-9]*)*-[0-9a-f]{12}([^a-z0-9]|$)'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
files="$work/files"
paths="$work/paths"

{
  if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    git ls-files -z --cached --others --exclude-standard
  else
    find . \( -path ./.git -o -path ./docs/superpowers -o -path ./tests/fixtures -o -name node_modules \) -prune \
      -o -type f -print0
  fi
} | {
  shopt -s nocasematch
  while IFS= read -r -d '' f; do
    f=${f#./}
    case $f in
      tests/fixtures/* | docs/superpowers/* | scripts/check-leaks.sh | .leak-terms.local | node_modules/* | */node_modules/*) continue ;;
      *.png | *.jpg | *.jpeg | *.gif | *.webp | *.ico | *.mp4 | *.mov | *.woff | *.woff2 | *.ttf | *.otf | *.pdf | *.zip) continue ;;
    esac
    if [ -f "$f" ]; then printf '%s\0' "$f"; fi
  done
} > "$files"
tr '\0' '\n' < "$files" | awk '{ print $0 ":0:" $0 }' > "$paths"

found=0

search() {
  xargs -0 sh -c 'grep "$@"; [ $? -le 1 ]' sh "$@" /dev/null < "$files" ||
    { echo "check-leaks: grep failed, the scan is incomplete" >&2; return 2; }
}

emit() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
    found=1
  fi
}

# Allowed matches are blanked out of each line before the company and name rules look at it.
mask_awk='
function blank(n,   s) { s = ""; while (n-- > 0) s = s " "; return s }
function mask(re,   off, a) {
  off = 1
  while (match(substr(o, off), re) && RLENGTH > 0) {
    a = off + RSTART - 1
    o = substr(o, 1, a - 1) blank(RLENGTH) substr(o, a + RLENGTH)
    off = a + RLENGTH
  }
}
BEGIN { n_allow = split(ENVIRON["LEAK_ALLOW_LIST"], allow, "\n") }
{
  p = index($0, ":"); path = substr($0, 1, p - 1); rest = substr($0, p + 1)
  q = index(rest, ":"); line = substr(rest, 1, q - 1); o = substr(rest, q + 1)
  for (i = 1; i <= n_allow; i++) if (allow[i] != "") mask(allow[i])
  s = tolower(o)
  sub(/^\.\//, "", path)
}'

# Prints path:line: [tag] match for the first company term on each line.
company_awk="$mask_awk"'
{
  hit = ""; off = 1
  while (match(substr(s, off), re)) {
    a = off + RSTART - 1; z = RLENGTH
    pc = a > 1 ? substr(o, a - 1, 1) : ""; nc = substr(o, a + z, 1)
    left = pc !~ /[A-Za-z0-9]/ || (pc ~ /[a-z]/ && substr(o, a, 1) ~ /[A-Z]/)
    right = nc !~ /[A-Za-z0-9]/ || (nc ~ /[A-Z]/ && substr(o, a + z - 1, 1) ~ /[a-z0-9]/)
    if (left && right) { hit = substr(s, a, z); break }
    off = a + 1
  }
  if (hit == "" && match(s, "(" re ")-[0-9]+")) hit = substr(s, RSTART, RLENGTH)
  if (hit == "") next
  printf "%s:%s: [%s] %s\n", path, line, tag, hit
}'

# Prints every name match on each line, the way grep -o does.
name_awk="$mask_awk"'
{
  t = s; base = 0
  while (match(t, ENVIRON["LEAK_NAME_RE"])) {
    a = base + RSTART; z = RLENGTH
    m = substr(o, a, z)
    gsub(/^[^A-Za-z0-9]+|[^A-Za-z0-9]+$/, "", m)
    printf "%s:%s: [name] %s\n", path, line, m
    t = "0" substr(s, a + z); base = a + z - 2
  }
}'

scan_company() {
  local hits
  hits=$(search -naHiE -- "$terms" | awk -v tag=company -v re="$terms" "$company_awk") || exit 2
  emit "$hits"
  hits=$(awk -v tag=company-path -v re="$terms" "$company_awk" "$paths")
  emit "$hits"
}

scan_names() {
  local hits
  hits=$(search -naHiE -- "$names" | LEAK_NAME_RE=$(printf '%s' "$names" | tr 'A-Z' 'a-z') awk "$name_awk") || exit 2
  emit "$hits"
}

scan_name_paths() {
  local hits
  hits=$({ grep -iE -- "$names" "$paths" || true; } | while IFS= read -r l; do
    p=${l%%:0:*}
    m=$(printf '%s\n' "$p" | grep -oiE -- "$names" | head -n 1 | sed 's/^[^A-Za-z0-9]*//; s/[^A-Za-z0-9]*$//')
    printf '%s:0: [name-path] %s\n' "$p" "$m"
  done)
  emit "$hits"
}

scan() {
  local tag=$1 opts=$2 pattern=$3 hits
  hits=$(search "$opts" -- "$pattern" |
    awk -v tag="$tag" '{
      p = index($0, ":"); path = substr($0, 1, p - 1); rest = substr($0, p + 1)
      q = index(rest, ":"); line = substr(rest, 1, q - 1); m = substr(rest, q + 1)
      gsub(/^[^A-Za-z0-9]+|[^A-Za-z0-9]+$/, "", m)
      if (tag == "notion-id" && m ~ /^[0x-]+$/) next
      sub(/^\.\//, "", path)
      printf "%s:%s: [%s] %s\n", path, line, tag, m
    }') || exit 2
  emit "$hits"
}

# Slack ids are C/U/G/D/W/T plus 8-10 uppercase letters or digits, and always carry a digit; this keeps words like CHANGELOG out.
scan_slack() {
  local hits
  hits=$(search -naHE -- '[CUGDWT][0-9A-Z]{8,10}' |
    awk '{
      p = index($0, ":"); path = substr($0, 1, p - 1); rest = substr($0, p + 1)
      q = index(rest, ":"); line = substr(rest, 1, q - 1); text = substr(rest, q + 1)
      sub(/^\.\//, "", path)
      n = split(text, tok, /[^A-Za-z0-9]+/)
      for (i = 1; i <= n; i++) {
        t = tok[i]
        if (t ~ /^[CUGDWT][0-9A-Z]+$/ && length(t) >= 9 && length(t) <= 11 && t ~ /[0-9]/)
          printf "%s:%s: [slack-id] %s\n", path, line, t
      }
    }') || exit 2
  emit "$hits"
}

scan_company
scan_name_paths
scan_names
scan notion-id -naHoiE "$notion"
scan linear-id -naHoE "$linear"
scan_slack
if [ -n "$phrases" ]; then scan phrase -naHoiE "${b}($phrases)"; fi

exit "$found"
