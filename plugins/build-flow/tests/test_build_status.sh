#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

out=$("$BIN" --repo acme/widgets 2>&1); rc=$?
assert_eq "exits 0 on success" "$rc" 0
assert_contains "names the repo" "$out" "repo=acme/widgets"
assert_contains "counts epics" "$out" "epic   open=1 closed=0"
assert_contains "counts stories" "$out" "story  open=1 closed=0"
assert_contains "counts tasks" "$out" "task   open=3 closed=1"
assert_contains "progress percent" "$out" "progress=25%"
ready=$(printf '%s\n' "$out" | sed -n '/^ready now/,/^$/p')
assert_contains "task with closed blocker is ready" "$ready" "#4 Task 1.1.2: Session API [parallel-safe]"
assert_not_contains "task with open blocker is not ready" "$ready" "#5 "
assert_not_contains "blocked label is not ready" "$ready" "#6 Task"
assert_not_contains "closed task is not ready" "$ready" "#3 Task"
assert_not_contains "non-plan issues ignored" "$out" "Unrelated bug"
assert_contains "lists waiting task with its blockers" "$out" "#5 Task 1.1.3: Logout <- #4"
assert_contains "lists blocked-label task" "$out" "#6 Task 1.1.4: Audit log <- blocked label"

log=$(mktemp); GH_STUB_LOG=$log "$BIN" --repo acme/widgets --milestone "Epic 1: Auth" >/dev/null
assert_contains "passes milestone filter to gh" "$(cat "$log")" "--milestone Epic 1: Auth"
assert_contains "always passes --repo to gh" "$(cat "$log")" "--repo acme/widgets"
rm -f "$log"

out=$("$BIN" 2>&1); rc=$?
assert_eq "defaults repo from gh repo view" "$rc" 0
assert_contains "default repo used" "$out" "repo=acme/widgets"

out=$("$BIN" --json --repo acme/widgets 2>&1)
assert_eq "json output is valid" "$(printf '%s' "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["tasks"]["open"])')" 3
assert_eq "json ready list" "$(printf '%s' "$out" | python3 -c 'import json,sys;print([i["number"] for i in json.load(sys.stdin)["ready"]])')" "[4]"

out=$(GH_STUB_AUTH=no "$BIN" --repo acme/widgets 2>&1); rc=$?
assert_eq "exit 3 when gh unauthenticated" "$rc" 3
assert_contains "auth hint" "$out" "gh auth login"

out=$("$BIN" --bogus 2>&1); rc=$?
assert_eq "exit 2 on unknown flag" "$rc" 2
assert_contains "usage on unknown flag" "$out" "usage: build-status"

out=$("$BIN" --help 2>&1); rc=$?
assert_eq "help exits 0" "$rc" 0

empty=$(mktemp); echo '[]' >"$empty"
out=$(GH_STUB_ISSUES=$empty "$BIN" --repo acme/widgets 2>&1); rc=$?
assert_eq "empty repo exits 0" "$rc" 0
assert_contains "empty repo hints build-plan" "$out" "/build-plan"
rm -f "$empty"

finish
