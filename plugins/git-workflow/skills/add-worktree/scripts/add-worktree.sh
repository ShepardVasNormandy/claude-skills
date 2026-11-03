#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: add-worktree.sh <branch> [worktree-path]

Creates a git worktree for <branch> beside the main worktree, at
<parent>/<repo>-<branch-last-segment> unless a path is given. A branch that is not
on the remote is created from the default branch.

Then copies the gitignored files and directories matching worktree_copy (read from
.claude/git-workflow.local.md in the main worktree) so the worktree is ready to build
and test. Default list: node_modules, .env*, .claude/*.local.md. A
pattern with a wildcard matches files only. Files named *.example or *.example.* are
skipped. In a pnpm repo it then runs a frozen offline install to relink
node_modules/.bin.

Run it from anywhere inside the repository.
EOF
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
esac

BRANCH=$1
MAIN_WORKTREE=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{ print substr($0, 10); exit }' || true)
[ -n "$MAIN_WORKTREE" ] || { echo "Error: run this from inside a git repository." >&2; exit 1; }

# Prints the value of a key from the config front matter, one line per list item.
config_get() {
  local file="$MAIN_WORKTREE/.claude/git-workflow.local.md"
  [ -f "$file" ] || return 0
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

WORKTREE_NAME=${BRANCH##*/}
PARENT_DIR=$(cd "$(dirname "$MAIN_WORKTREE")" && pwd)
if [ -n "${2:-}" ]; then
  WORKTREE_PATH=$2
  [[ "$WORKTREE_PATH" != /* ]] && WORKTREE_PATH="$PARENT_DIR/$(basename "$WORKTREE_PATH")"
else
  WORKTREE_PATH="$PARENT_DIR/$(basename "$MAIN_WORKTREE")-$WORKTREE_NAME"
fi

open_editor() {
  if command -v code >/dev/null 2>&1; then code "$1"; fi
}

if [ -d "$WORKTREE_PATH" ]; then
  echo "Worktree already exists at $WORKTREE_PATH"
  open_editor "$WORKTREE_PATH"
  exit 0
fi

cd "$MAIN_WORKTREE"
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
BASE=${BASE#origin/}
[ -n "$BASE" ] || BASE=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" { sub("^refs/heads/", "", $2); print $2; exit }' || true)
BASE=${BASE:-main}

git fetch origin "$BASE"
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git fetch origin "$BRANCH"
  git worktree add "$WORKTREE_PATH" "$BRANCH"
else
  echo "Branch '$BRANCH' not found on remote, creating from origin/$BASE..."
  git worktree add -b "$BRANCH" "$WORKTREE_PATH" "origin/$BASE"
fi

PATTERNS=$(config_get worktree_copy)
[ -n "$PATTERNS" ] || PATTERNS=$(printf '%s\n' node_modules '.env*' '.claude/*.local.md')

# Other worktrees nested inside the main one are skipped, so their files never leak in.
PRUNE=(-path "$MAIN_WORKTREE/.git")
while IFS= read -r w; do
  case $w in "$MAIN_WORKTREE"/*) PRUNE+=(-o -path "$w") ;; esac
done < <(git worktree list --porcelain | awk '/^worktree /{ print substr($0, 10) }')

echo "Copying gitignored files from the main worktree..."
while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  pattern=${pattern%/}
  case $pattern in
    */*) match=(-path "$MAIN_WORKTREE/$pattern") ;;
    *) match=(-name "$pattern") ;;
  esac
  case $pattern in *[*?[]*) match+=(-type f) ;; esac
  while IFS= read -r -d '' src; do
    rel=${src#"$MAIN_WORKTREE"/}
    case $rel in *.example | *.example.*) continue ;; esac
    git check-ignore -q -- "$rel" || continue
    dest="$WORKTREE_PATH/$rel"
    [ -e "$dest" ] && continue
    mkdir -p "$(dirname "$dest")"
    cp -R "$src" "$dest"
    echo "  -> $rel"
  done < <(find "$MAIN_WORKTREE" \( "${PRUNE[@]}" \) -prune -o "${match[@]}" -print0 -prune -o -name node_modules -prune 2>/dev/null || true)
done <<< "$PATTERNS"

# cp -R leaves pnpm's symlink farm (node_modules/.bin, the .pnpm store links) dangling.
# A frozen offline install relinks it without touching the lockfile.
if [ -f "$WORKTREE_PATH/pnpm-lock.yaml" ] && [ -d "$WORKTREE_PATH/node_modules" ]; then
  echo "Repairing node_modules (pnpm install --frozen-lockfile --prefer-offline)..."
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "  -> pnpm not found; run 'pnpm install' in the worktree before tests/commits"
  elif (cd "$WORKTREE_PATH" && pnpm install --frozen-lockfile --prefer-offline >/dev/null 2>&1); then
    echo "  -> node_modules ready (.bin relinked)"
  else
    echo "  -> WARNING: install failed; run 'pnpm install' in the worktree before tests/commits"
  fi
fi

open_editor "$WORKTREE_PATH"
echo "Done. Worktree ready at: $WORKTREE_PATH"
