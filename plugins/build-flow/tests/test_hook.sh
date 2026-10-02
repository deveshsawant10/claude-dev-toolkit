#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

HOOK="$HERE/../hooks/session-status.sh"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
repo="$SB/repo"
mkdir -p "$repo/docs"
git -C "$repo" init -q

ctx() { python3 -c 'import json,sys
d=json.load(sys.stdin); h=d["hookSpecificOutput"]
assert h["hookEventName"]=="SessionStart"; print(h["additionalContext"])'; }
run_hook() { printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1" | "$HOOK"; }

out=$(run_hook "$repo"); rc=$?
assert_eq "no opt-in file: exits 0" "$rc" 0
assert_eq "no opt-in file: silent" "$out" ""

touch "$repo/docs/idea-widgets.md"
out=$(run_hook "$repo"); rc=$?
assert_eq "opted in: exits 0" "$rc" 0
text=$(printf '%s' "$out" | ctx 2>&1)
assert_contains "valid hook JSON with progress" "$text" "build-flow: acme/widgets plan is 25% done (tasks 1/4 closed"
assert_contains "lists the ready task" "$text" "#4 Task 1.1.2: Session API [parallel-safe]"
assert_not_contains "does not list waiting tasks" "$text" "#5 "
assert_contains "points at /execute-build" "$text" "/execute-build"

rm "$repo/docs/idea-widgets.md"; touch "$repo/docs/build-plan-widgets.md"
out=$(run_hook "$repo")
assert_contains "build-plan file also opts in" "$(printf '%s' "$out" | ctx)" "plan is 25% done"

mkdir -p "$repo/src/deep"
out=$(run_hook "$repo/src/deep")
assert_contains "works from a subdirectory" "$(printf '%s' "$out" | ctx)" "plan is 25% done"

out=$(cd "$repo" && printf 'not json' | "$HOOK"); rc=$?
assert_eq "garbage payload: exits 0" "$rc" 0
assert_contains "garbage payload falls back to cwd" "$(printf '%s' "$out" | ctx)" "plan is 25% done"

out=$(GH_STUB_ISSUES="$HERE/fixtures/many-ready.json" run_hook "$repo")
text=$(printf '%s' "$out" | ctx)
assert_contains "caps the ready list" "$text" "... and 2 more"
assert_eq "shows at most 5 ready tasks" "$(printf '%s\n' "$text" | grep -c '^  #')" 5

empty="$SB/empty.json"; echo '[]' >"$empty"
out=$(GH_STUB_ISSUES=$empty run_hook "$repo"); rc=$?
assert_eq "no tasks: exits 0" "$rc" 0
assert_eq "no tasks: silent" "$out" ""

out=$(GH_STUB_AUTH=no run_hook "$repo"); rc=$?
assert_eq "gh not authed: exits 0" "$rc" 0
assert_eq "gh not authed: silent" "$out" ""

start=$SECONDS
out=$(GH_STUB_SLEEP=5 BUILD_FLOW_HOOK_TIMEOUT=1 run_hook "$repo"); rc=$?
assert_eq "slow gh: exits 0" "$rc" 0
assert_eq "slow gh: silent" "$out" ""
assert_eq "slow gh: gives up at the timeout" "$([ $((SECONDS - start)) -le 3 ] && echo fast)" fast

out=$(run_hook "$SB"); rc=$?
assert_eq "not a git repo: exits 0" "$rc" 0
assert_eq "not a git repo: silent" "$out" ""

out=$(run_hook "$SB/does-not-exist"); rc=$?
assert_eq "missing cwd: exits 0" "$rc" 0

finish
