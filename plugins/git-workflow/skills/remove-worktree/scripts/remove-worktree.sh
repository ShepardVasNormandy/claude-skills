#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-worktree.sh <branch> [worktree-path] [--force]
       remove-worktree.sh --list

Safely removes a worktree created by add-worktree.sh. The path defaults to
<parent>/<repo>-<branch-last-segment>, beside the main worktree; a relative path is
resolved against the main worktree's parent.

Refuses (exit 2) when the worktree is dirty, has unpushed commits, has commits after
its merged PR, or its PR is not merged, unless --force is given (anywhere in the
arguments). A branch that still tracks origin/<default branch> counts as never
pushed. Uses `git worktree remove` (never rm -rf), deletes the local branch, and
prunes stale remote refs. With no branch, or with --list, prints the removable worktrees.

Run it from anywhere inside the repository.
EOF
}

# Parse args: --force/--list anywhere; first two positionals are branch + optional path.
FORCE=0
LIST=0
POSITIONAL=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --list|-l) LIST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) POSITIONAL+=("$a") ;;
  esac
done
# No branch given → just list the removable worktrees.
[[ -z "${POSITIONAL[0]:-}" ]] && LIST=1

MAIN_WORKTREE=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{ print substr($0, 10); exit }' || true)
[[ -n "$MAIN_WORKTREE" ]] || { echo "Error: run this from inside a git repository." >&2; exit 1; }
cd "$MAIN_WORKTREE"
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
BASE=${BASE#origin/}
[[ -n "$BASE" ]] || BASE=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" { sub("^refs/heads/", "", $2); print $2; exit }' || true)
BASE=${BASE:-main}

# --list (or no branch): print the removable worktrees (everything except main) and exit.
if [[ "$LIST" -eq 1 ]]; then
  echo "Removable worktrees for $MAIN_WORKTREE:"
  if [[ -z "$(git worktree list | awk -v main="$MAIN_WORKTREE" '$1!=main')" ]]; then
    echo "  (none — only the main worktree exists)"
  else
    git worktree list | awk -v main="$MAIN_WORKTREE" '$1!=main {print "  " $0}'
  fi
  echo
  echo "Remove one with: $(basename "$0") <branch>"
  exit 0
fi

BRANCH="${POSITIONAL[0]}"
WORKTREE_NAME="${BRANCH##*/}"
if [[ -n "${POSITIONAL[1]:-}" ]]; then
  WORKTREE_PATH="${POSITIONAL[1]}"
  [[ "$WORKTREE_PATH" != /* ]] && WORKTREE_PATH="$(cd "$(dirname "$MAIN_WORKTREE")" && pwd)/$(basename "$WORKTREE_PATH")"
else
  # Default sits beside the main worktree: <parent>/<repo>-<segment>.
  WORKTREE_PATH="$(cd "$(dirname "$MAIN_WORKTREE")" && pwd)/$(basename "$MAIN_WORKTREE")-$WORKTREE_NAME"
fi

# Normalize to the resolved absolute path git uses, then confirm it's a registered worktree.
[[ -d "$WORKTREE_PATH" ]] && WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd)"
if [[ "$WORKTREE_PATH" == "$MAIN_WORKTREE" ]]; then
  echo "Error: refusing to remove the main worktree ($MAIN_WORKTREE)." >&2
  exit 1
fi
if ! git worktree list --porcelain | grep -qxF "worktree $WORKTREE_PATH"; then
  echo "Error: '$WORKTREE_PATH' is not a registered worktree of $MAIN_WORKTREE." >&2
  echo "Known worktrees:" >&2
  git worktree list >&2
  exit 1
fi

echo "Target worktree: $WORKTREE_PATH"
echo "Branch:          $BRANCH"
echo

# --- Safety checks -----------------------------------------------------------
BLOCKERS=()

# 1. Uncommitted or untracked changes.
if [[ -n "$(git -C "$WORKTREE_PATH" status --porcelain)" ]]; then
  BLOCKERS+=("uncommitted or untracked changes in the worktree")
fi

# 2. Is every local commit merged? Proven when the branch tip is in origin/<default branch>,
#    or when gh reports the PR MERGED and the tip is contained in the PR head that was merged.
#    A squash merge leaves the tip outside the default branch, hence the PR head check.
git fetch origin "$BASE" --quiet 2>/dev/null || echo "  (warning: could not fetch origin/$BASE — merge check may be stale)"
TIP=$(git rev-parse --verify --quiet "refs/heads/$BRANCH" || true)
MERGED=0
PR_STATE=""
if [[ -n "$TIP" ]] && git merge-base --is-ancestor "$TIP" "origin/$BASE" 2>/dev/null; then
  MERGED=1
elif command -v gh >/dev/null 2>&1; then
  PR_INFO=$(gh pr view "$BRANCH" --json state,headRefOid -q '.state + " " + .headRefOid' 2>/dev/null || true)
  PR_STATE=${PR_INFO%% *}
  PR_HEAD=${PR_INFO#* }
  if [[ "$PR_STATE" == "MERGED" && -n "$TIP" && -n "$PR_HEAD" ]]; then
    git cat-file -e "$PR_HEAD^{commit}" 2>/dev/null || git fetch origin "$PR_HEAD" --quiet 2>/dev/null || true
    git merge-base --is-ancestor "$TIP" "$PR_HEAD" 2>/dev/null && MERGED=1
  fi
fi
if [[ "$MERGED" -eq 0 ]]; then
  if [[ "$PR_STATE" == "MERGED" ]]; then
    BLOCKERS+=("commits after the merged PR; use --force to discard")
  else
    BLOCKERS+=("PR for '$BRANCH' is not merged")
  fi
fi

# 3. Unpushed commits. add-worktree tracks origin/<default branch> until the first push,
#    so that upstream counts as no pushed branch. Once every commit is proven merged,
#    commits ahead of a stale remote branch are only noted. A merged PR with later
#    commits is already blocked above.
UPSTREAM=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
if [[ -n "$UPSTREAM" && "$UPSTREAM" != "origin/$BASE" ]]; then
  AHEAD="$(git -C "$WORKTREE_PATH" log --oneline '@{upstream}..HEAD')"
  if [[ -n "$AHEAD" ]]; then
    if [[ "$MERGED" -eq 1 ]]; then
      echo "  (note: $(printf '%s\n' "$AHEAD" | grep -c .) local commit(s) not on the remote branch, but they are in the merged PR)"
    elif [[ "$PR_STATE" != "MERGED" ]]; then
      BLOCKERS+=("unpushed commits on $BRANCH")
    fi
  fi
elif [[ "$MERGED" -eq 0 && "$PR_STATE" != "MERGED" ]]; then
  BLOCKERS+=("branch '$BRANCH' was never pushed (no upstream, or it still tracks origin/$BASE)")
fi

# --- Decide ------------------------------------------------------------------
if [[ ${#BLOCKERS[@]} -gt 0 && "$FORCE" -eq 0 ]]; then
  echo "BLOCKED — not safe to remove this worktree:" >&2
  for b in "${BLOCKERS[@]}"; do echo "  - $b" >&2; done
  echo >&2
  echo "Re-run with --force to remove it anyway." >&2
  exit 2
fi

# --- Remove ------------------------------------------------------------------
if [[ "$FORCE" -eq 1 ]]; then
  git worktree remove --force "$WORKTREE_PATH"
else
  git worktree remove "$WORKTREE_PATH"
fi
echo "Removed worktree: $WORKTREE_PATH"

if git branch -d "$BRANCH" 2>/dev/null; then
  echo "Deleted local branch: $BRANCH"
elif [[ "$FORCE" -eq 1 || "$MERGED" -eq 1 ]]; then
  git branch -D "$BRANCH" && echo "Force-deleted local branch: $BRANCH"
else
  echo "Kept local branch '$BRANCH' (not fully merged). Delete with: git branch -D $BRANCH"
fi

git fetch --prune --quiet 2>/dev/null && echo "Pruned stale remote-tracking refs."
echo "Done."
