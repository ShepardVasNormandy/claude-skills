#!/usr/bin/env bash
set -euo pipefail

skills=$(cd "$(dirname "$0")/../skills" && pwd)
FIXTURES=$(cd "$(dirname "$0")/fixtures" && pwd)
export FIXTURES
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'
  failures=$((failures + 1))
}

# gh stub: GH_STUB names a handler file that answers the calls a test expects; any other
# call fails loudly so it shows up. The code stub does nothing.
mkdir "$work/bin"
printf '#!/usr/bin/env bash\n[ -z "${GH_STUB:-}" ] || . "$GH_STUB"\necho "stub gh called: $*" >&2\nexit 99\n' > "$work/bin/gh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/code"
chmod +x "$work/bin/gh" "$work/bin/code"
export PATH="$work/bin:$PATH"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

for s in \
  flaky-tests/scripts/flaky-tests.sh \
  flaky-tests/scripts/fetch-e2e-annotations.sh \
  stack/scripts/stack-status.sh \
  gh-pr-status/scripts/gh-pr-status.sh \
  add-worktree/scripts/add-worktree.sh \
  remove-worktree/scripts/remove-worktree.sh; do
  code=0
  out=$(cd "$work" && bash "$skills/$s" --help 2>&1) || code=$?
  if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -q 'Usage' && ! printf '%s\n' "$out" | grep -q 'stub gh'; then
    ok "$s --help exits 0 offline"
  else
    not_ok "$s --help exits 0 offline (exit $code)" "$out"
  fi
done

for pair in "flaky-tests.sh:test_workflow" "fetch-e2e-annotations.sh:e2e_workflow"; do
  s=${pair%%:*}
  key=${pair#*:}
  code=0
  out=$(cd "$work" && bash "$skills/flaky-tests/scripts/$s" 5 2>&1) || code=$?
  if [ "$code" -eq 1 ] && printf '%s\n' "$out" | grep -q "$key" && ! printf '%s\n' "$out" | grep -q 'stub gh'; then
    ok "$s names the missing config key before calling gh"
  else
    not_ok "$s names the missing config key before calling gh (exit $code)" "$out"
  fi
done

git init -q --bare "$work/origin.git"
git -C "$work/origin.git" symbolic-ref HEAD refs/heads/main
git init -q "$work/seed"
git -C "$work/seed" symbolic-ref HEAD refs/heads/main
mkdir -p "$work/seed/services/orders-service"
printf 'node_modules/\n.env*\n!.env.example\nconfig*.json\n*.local.md\ndist/\n' > "$work/seed/.gitignore"
printf '{}\n' > "$work/seed/package.json"
git -C "$work/seed" add -A
git -C "$work/seed" commit -qm "chore: init"
git -C "$work/seed" push -q "$work/origin.git" main
git clone -q "$work/origin.git" "$work/web-app"

main="$work/web-app"
mkdir -p "$main/node_modules/left-pad" "$main/services/orders-service/node_modules/zod" "$main/dist" "$main/.claude" "$main/tools/.env/bin"
printf 'x\n' > "$main/tools/.env/bin/python"
printf -- '---\nnote: x\n---\n' > "$main/.claude/team.local.md"
printf 'x\n' > "$main/node_modules/left-pad/index.js"
printf 'x\n' > "$main/services/orders-service/node_modules/zod/index.js"
printf 'SECRET=1\n' > "$main/.env"
printf 'SECRET=2\n' > "$main/services/orders-service/.env.local"
printf 'SECRET=\n' > "$main/.env.example"
printf '{}\n' > "$main/services/orders-service/config.test.json"
printf 'x\n' > "$main/dist/bundle.js"

check_copy() {
  local desc=$1 wt=$2 path want=yes
  shift 2
  for path in "$@"; do
    case $path in
      !*) want=no; path=${path#!} ;;
      *) want=yes ;;
    esac
    if { [ "$want" = yes ] && [ -e "$wt/$path" ]; } || { [ "$want" = no ] && [ ! -e "$wt/$path" ]; }; then
      ok "$desc: $path $([ "$want" = yes ] && echo copied || echo skipped)"
    else
      not_ok "$desc: $path $([ "$want" = yes ] && echo copied || echo skipped)"
    fi
  done
}

code=0
out=$(cd "$main" && bash "$skills/add-worktree/scripts/add-worktree.sh" jdoe/ord-123-defaults 2>&1) || code=$?
wt="$work/web-app-ord-123-defaults"
if [ "$code" -eq 0 ] && [ -f "$wt/package.json" ]; then ok "add-worktree creates <repo>-<branch-slug>"; else not_ok "add-worktree creates <repo>-<branch-slug> (exit $code)" "$out"; fi
check_copy "default list" "$wt" node_modules/left-pad/index.js services/orders-service/node_modules/zod/index.js .env \
  services/orders-service/.env.local .claude/team.local.md \
  '!services/orders-service/config.test.json' '!.env.example' '!dist' '!tools/.env'

printf -- '---\nticket_in: none\nworktree_copy:\n  - dist\n  - "*.local.md"\n---\n' > "$main/.claude/git-workflow.local.md"
code=0
out=$(cd "$main" && bash "$skills/add-worktree/scripts/add-worktree.sh" jdoe/ord-124-block-list 2>&1) || code=$?
wt="$work/web-app-ord-124-block-list"
[ "$code" -eq 0 ] || not_ok "add-worktree with a block list (exit $code)" "$out"
check_copy "block list" "$wt" dist/bundle.js .claude/git-workflow.local.md '!node_modules' '!.env'

printf -- '---\nworktree_copy: [".env*", config*.json]\n---\n' > "$main/.claude/git-workflow.local.md"
code=0
out=$(cd "$main" && bash "$skills/add-worktree/scripts/add-worktree.sh" ord-125 2>&1) || code=$?
wt="$work/web-app-ord-125"
[ "$code" -eq 0 ] || not_ok "add-worktree with an inline list (exit $code)" "$out"
check_copy "inline list" "$wt" .env services/orders-service/config.test.json '!node_modules' '!dist'

remove="$skills/remove-worktree/scripts/remove-worktree.sh"
printf 'change\n' > "$work/web-app-ord-125/feature.txt"
git -C "$work/web-app-ord-125" add feature.txt
git -C "$work/web-app-ord-125" commit -qm "feat: change"
code=0
out=$(cd "$main" && bash "$remove" ord-125 2>&1) || code=$?
if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -q 'not merged' && [ -d "$work/web-app-ord-125" ]; then
  ok "remove-worktree blocks an unmerged branch"
else
  not_ok "remove-worktree blocks an unmerged branch (exit $code)" "$out"
fi

code=0
out=$(cd "$work/web-app-ord-123-defaults" && bash "$remove" jdoe/ord-123-defaults 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ ! -d "$work/web-app-ord-123-defaults" ] && ! git -C "$main" rev-parse -q --verify refs/heads/jdoe/ord-123-defaults >/dev/null; then
  ok "remove-worktree removes a merged branch from inside its worktree"
else
  not_ok "remove-worktree removes a merged branch from inside its worktree (exit $code)" "$out"
fi

code=0
out=$(cd "$main" && bash "$remove" --list 2>&1) || code=$?
if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -q 'web-app-ord-125' && ! printf '%s\n' "$out" | grep -q 'ord-123'; then
  ok "remove-worktree --list shows the remaining worktrees"
else
  not_ok "remove-worktree --list shows the remaining worktrees (exit $code)" "$out"
fi

new_branch_worktree() {
  local branch=$1 out code=0
  out=$(cd "$main" && bash "$skills/add-worktree/scripts/add-worktree.sh" "$branch" 2>&1) || code=$?
  [ "$code" -eq 0 ] || not_ok "add-worktree $branch (exit $code)" "$out"
}

cat > "$work/gh-pr-view.sh" <<'EOF'
case "$*" in
  "pr view $PR_BRANCH --json state,headRefOid -q"*) echo "MERGED $PR_HEAD"; exit 0 ;;
esac
EOF

new_branch_worktree ord-130
git -C "$work/web-app-ord-130" commit -q --allow-empty -m "feat: squashed into the PR"
head=$(git -C "$work/web-app-ord-130" rev-parse HEAD)
code=0
out=$(cd "$main" && GH_STUB="$work/gh-pr-view.sh" PR_BRANCH=ord-130 PR_HEAD=$head bash "$remove" ord-130 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ ! -d "$work/web-app-ord-130" ]; then
  ok "remove-worktree removes a branch whose tip is the merged PR head"
else
  not_ok "remove-worktree removes a branch whose tip is the merged PR head (exit $code)" "$out"
fi

new_branch_worktree ord-131
git -C "$work/web-app-ord-131" commit -q --allow-empty -m "feat: merged"
head=$(git -C "$work/web-app-ord-131" rev-parse HEAD)
git -C "$work/web-app-ord-131" commit -q --allow-empty -m "feat: after the merge"
code=0
out=$(cd "$main" && GH_STUB="$work/gh-pr-view.sh" PR_BRANCH=ord-131 PR_HEAD=$head bash "$remove" ord-131 2>&1) || code=$?
if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -q 'commits after the merged PR' && [ -d "$work/web-app-ord-131" ]; then
  ok "remove-worktree blocks a merged PR with a later local commit"
else
  not_ok "remove-worktree blocks a merged PR with a later local commit (exit $code)" "$out"
fi

new_branch_worktree ord-132
git -C "$work/web-app-ord-132" commit -q --allow-empty -m "feat: merged"
head=$(git -C "$work/web-app-ord-132" rev-parse HEAD)
printf 'draft\n' > "$work/web-app-ord-132/notes.txt"
code=0
out=$(cd "$main" && GH_STUB="$work/gh-pr-view.sh" PR_BRANCH=ord-132 PR_HEAD=$head bash "$remove" ord-132 2>&1) || code=$?
if [ "$code" -eq 2 ] && printf '%s\n' "$out" | grep -q 'uncommitted' && [ -f "$work/web-app-ord-132/notes.txt" ]; then
  ok "remove-worktree blocks a dirty worktree even when the PR is merged"
else
  not_ok "remove-worktree blocks a dirty worktree even when the PR is merged (exit $code)" "$out"
fi

git init -q --bare -b master "$work/legacy.git"
git init -q -b master "$work/legacy"
git -C "$work/legacy" commit -q --allow-empty -m "chore: init"
git -C "$work/legacy" remote add origin "$work/legacy.git"
git -C "$work/legacy" push -q origin master
code=0
out=$(cd "$work/legacy" && bash "$skills/add-worktree/scripts/add-worktree.sh" feat-x 2>&1) || code=$?
if [ "$code" -eq 0 ] && [ -d "$work/legacy-feat-x" ] && printf '%s\n' "$out" | grep -q 'origin/master'; then
  ok "add-worktree finds the default branch from the remote when origin/HEAD is unset"
else
  not_ok "add-worktree finds the default branch from the remote when origin/HEAD is unset (exit $code)" "$out"
fi

cat > "$work/gh-unit.sh" <<'EOF'
case "$*" in
  "repo view --json nameWithOwner --jq .nameWithOwner") echo acme/web-app; exit 0 ;;
  "repo view acme/web-app --json defaultBranchRef --jq .defaultBranchRef.name") echo main; exit 0 ;;
  "run list --repo acme/web-app --workflow ci.yml --limit 4 "*)
    printf '%s\t%s\t%s\n' 101 2026-10-03T10:00:00Z feat-a 102 2026-10-02T10:00:00Z feat-b \
      103 2026-10-01T10:00:00Z feat-a 104 2026-09-30T10:00:00Z main
    exit 0 ;;
  "run view 101 --repo acme/web-app --json jobs "*) echo '{"id":11,"conclusion":"failure"}'; exit 0 ;;
  "run view 102 --repo acme/web-app --json jobs "*) echo '{"id":12,"conclusion":"failure"}'; exit 0 ;;
  "run view 103 --repo acme/web-app --json jobs "*) echo '{"id":13,"conclusion":"failure"}'; exit 0 ;;
  "run view 104 --repo acme/web-app --json jobs "*) echo '{"id":14,"conclusion":"success"}'; exit 0 ;;
  "run view --repo acme/web-app --job 11 --log-failed" | "run view --repo acme/web-app --job 12 --log-failed")
    cat "$FIXTURES/jest-flaky.log"; exit 0 ;;
  "run view --repo acme/web-app --job 13 --log-failed") cat "$FIXTURES/jest-break.log"; exit 0 ;;
esac
EOF
unit_env() { (cd "$work" && GH_STUB="$work/gh-unit.sh" TEST_WORKFLOW=ci.yml TEST_JOB="checks / unit-tests" CSV="$work/flaky.csv" JOBS=2 "$@"); }
code=0
out=$(unit_env bash "$skills/flaky-tests/scripts/flaky-tests.sh" 4 --json 2>"$work/unit.err") || code=$?
flaky=$(printf '%s\n' "$out" | jq -c '.[] | select(.test == "refund › retries after a gateway timeout") | [.file, .count, .total, .branchCount, .likelyFlaky]' 2>/dev/null || true)
single=$(printf '%s\n' "$out" | jq -c '.[] | select(.test == "cart total › applies the coupon once") | [.count, .branchCount, .likelyFlaky]' 2>/dev/null || true)
if [ "$code" -eq 0 ] && [ "$flaky" = '["src/api/orders/refund.test.ts",2,4,2,true]' ] && [ "$single" = '[1,1,false]' ] &&
  [ "$(printf '%s\n' "$out" | jq length 2>/dev/null)" = 2 ]; then
  ok "flaky-tests ranks a test failing on two branches as likely flaky"
else
  not_ok "flaky-tests ranks a test failing on two branches as likely flaky (exit $code)" "$out
$(cat "$work/unit.err")"
fi
code=0
out=$(unit_env bash "$skills/flaky-tests/scripts/flaky-tests.sh" 4 2>&1) || code=$?
section=$(printf '%s\n' "$out" | awk '/LIKELY FLAKY/ { on = 1; next } /SINGLE-BRANCH/ { on = 0 } on')
if [ "$code" -eq 0 ] && printf '%s\n' "$section" | grep -q '50% (2/4)  2b  (last seen 2026-10-03)  refund › retries after a gateway timeout' &&
  ! printf '%s\n' "$section" | grep -q 'applies the coupon once' &&
  grep -q '^13,2026-10-01T10:00:00Z,failure,feat-a,"src/web/cart/total.test.ts::' "$work/flaky.csv"; then
  ok "flaky-tests report lists the two-branch failure under LIKELY FLAKY and writes the CSV"
else
  not_ok "flaky-tests report lists the two-branch failure under LIKELY FLAKY and writes the CSV (exit $code)" "$out"
fi

cat > "$work/gh-e2e.sh" <<'EOF'
case "$*" in
  "run list -w e2e.yml -b main -R acme/web-app -L 3 --json databaseId,conclusion,createdAt,attempt")
    cat "$FIXTURES/e2e/runs.json"; exit 0 ;;
  "api repos/acme/web-app/actions/runs/"*"/jobs --paginate")
    id=${2#repos/acme/web-app/actions/runs/}; cat "$FIXTURES/e2e/jobs-${id%%/*}.pages"; exit 0 ;;
  "api repos/acme/web-app/check-runs/"*"/annotations --paginate")
    id=${2#repos/acme/web-app/check-runs/}; cat "$FIXTURES/e2e/annotations-${id%%/*}.pages"; exit 0 ;;
esac
EOF
e2e_env() { (cd "$work" && GH_STUB="$work/gh-e2e.sh" E2E_WORKFLOW=e2e.yml REPO=acme/web-app BRANCH=main "$@"); }
code=0
out=$(e2e_env bash "$skills/flaky-tests/scripts/fetch-e2e-annotations.sh" 3 2>&1) || code=$?
if [ "$code" -eq 0 ] &&
  printf '%s\n' "$out" | grep -qF '| 1 | checkout > pays with a saved card | checkout.spec.ts | 2/3 | 67% |' &&
  printf '%s\n' "$out" | grep -qF '| 2 | cart > keeps items after reload | cart.spec.ts | 1/3 | 33% |' &&
  printf '%s\n' "$out" | grep -qF '| Unique failing tests | 2 |' &&
  printf '%s\n' "$out" | grep -qF '| 1 | 2026-10-03T08:00:00Z | [201](https://github.com/acme/web-app/actions/runs/201) | failure | 2 |'; then
  ok "fetch-e2e-annotations aggregates every job and every annotation page"
else
  not_ok "fetch-e2e-annotations aggregates every job and every annotation page (exit $code)" "$out"
fi
code=0
out=$(e2e_env env E2E_JOB="playwright (1/2)" bash "$skills/flaky-tests/scripts/fetch-e2e-annotations.sh" 3 2>&1) || code=$?
if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -qF '| Unique failing tests | 1 |' && ! printf '%s\n' "$out" | grep -q 'keeps items after reload'; then
  ok "fetch-e2e-annotations reads only the configured job"
else
  not_ok "fetch-e2e-annotations reads only the configured job (exit $code)" "$out"
fi

cat > "$work/gh-stack.sh" <<'EOF'
case "$*" in
  "extension list") printf 'gh stack\tgithub/gh-stack\tv0.1.0\n'; exit 0 ;;
  "stack view --json")
    echo '{"trunk":"main","branches":[{"name":"feat-a","isCurrent":false,"isMerged":false,"isQueued":false,"needsRebase":false,"pr":{"number":7}},{"name":"feat-b","isCurrent":true,"isMerged":false,"isQueued":false,"needsRebase":true,"pr":{"number":8}}]}'
    exit 0 ;;
  "pr view 7 --json "*)
    echo '{"number":7,"reviewDecision":"","state":"OPEN","isDraft":false,"author":{"login":"jdoe"},"reviews":[{"author":{"login":"asmith"},"state":"COMMENTED"}],"statusCheckRollup":[{"name":"unit-tests","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/web-app/actions/runs/1/job/555"}]}'
    exit 0 ;;
  "pr view 8 --json "*) echo "GraphQL: something went wrong" >&2; exit 1 ;;
esac
EOF
code=0
out=$(cd "$main" && GH_STUB="$work/gh-stack.sh" bash "$skills/stack/scripts/stack-status.sh" 2>&1) || code=$?
if [ "$code" -eq 0 ] && printf '%s\n' "$out" | grep -qF '> #8  feat-b (needs rebase)' &&
  printf '%s\n' "$out" | grep -qF 'unit-tests  (job 555)' && printf '%s\n' "$out" | grep -qF 'reviewed: asmith commented'; then
  ok "stack-status prints the stack under set -e when one PR lookup fails"
else
  not_ok "stack-status prints the stack under set -e when one PR lookup fails (exit $code)" "$out"
fi

printf -- '---\ntest_workflow: ci.yml\ntest_job: "checks / unit-tests"\ne2e_workflow: e2e.yml\n---\n' > "$main/.claude/git-workflow.local.md"
for s in flaky-tests.sh fetch-e2e-annotations.sh; do
  code=0
  out=$(cd "$work/web-app-ord-125" && bash "$skills/flaky-tests/scripts/$s" 5 2>&1) || code=$?
  if printf '%s\n' "$out" | grep -q 'stub gh called: repo view'; then
    ok "$s reads its keys from the main worktree's config"
  else
    not_ok "$s reads its keys from the main worktree's config (exit $code)" "$out"
  fi
done

[ "$failures" -eq 0 ]
