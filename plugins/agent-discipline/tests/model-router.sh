#!/usr/bin/env bash
# Checks that route.mjs falls back silently with no key and on HTTP 402, and reports an error on other non-2xx answers.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
route="$here/../skills/model-router/scripts/route.mjs"
failures=0

check() {
  if [ "$2" = "$3" ]; then
    printf 'ok - %s\n' "$1"
  else
    printf 'not ok - %s\n    got:  %s\n    want: %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

code=0
out=$(env -u TYPESAFE_API_KEY node "$route" --tool claude-code "Rename foo to bar." 2>&1) || code=$?
check "no key prints fallback" "$out" '{"fallback":true}'
check "no key exits 0" "$code" 0

answer() {
  ROUTE="$route" STATUS=$1 node --input-type=module -e '
    const { route } = await import(process.env.ROUTE);
    const fetch = async () => ({ ok: false, status: Number(process.env.STATUS) });
    console.log(JSON.stringify(await route("x", {}, {}, {}, { fetch, key: "k", base: "http://127.0.0.1:9" })));
  ' 2>&1
}
check "HTTP 402 returns fallback" "$(answer 402)" '{"fallback":true,"status":402}'
check "HTTP 401 returns an error" "$(answer 401)" '{"error":"Jev answered 401"}'

[ "$failures" -eq 0 ]
