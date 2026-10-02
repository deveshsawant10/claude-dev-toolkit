#!/usr/bin/env bash
# SessionStart hook: in a repo that uses build-flow, tell the session how far
# the plan is and which tasks can start now.
#
# Rules this script must never break:
#   1. Always exit 0. A failing hook must never block a session from starting.
#   2. Stay silent unless the repo opted in (docs/idea-*.md or
#      docs/build-plan-*.md exists) and there is something to report.
set -uo pipefail
trap 'exit 0' ERR

payload=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$(pwd)
cd "$cwd" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

opted_in=0
for f in "$root"/docs/idea-*.md "$root"/docs/build-plan-*.md; do
  [ -f "$f" ] && { opted_in=1; break; }
done
[ "$opted_in" = 1 ] || exit 0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
status_cmd="$here/../scripts/build_status.py"
[ -x "$status_cmd" ] || exit 0

limit=${BUILD_FLOW_HOOK_TIMEOUT:-8}
# macOS has no `timeout`; perl's alarm does the same job everywhere.
if command -v timeout >/dev/null 2>&1; then
  run_limited() { timeout "$limit" "$@"; }
else
  run_limited() { perl -e 'alarm shift; exec @ARGV' "$limit" "$@"; }
fi
report=$(cd "$root" && run_limited "$status_cmd" --json 2>/dev/null) || exit 0
[ -n "$report" ] || exit 0

printf '%s' "$report" | "$here/summarize.py" 2>/dev/null || true
exit 0
