#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

assert_eq "non-push command silent" "$(hook "$SANDBOX" "ls -la")" none
assert_eq "git status silent" "$(hook "$SANDBOX" "git status")" none
assert_eq "push outside a repo silent" "$(hook "$SANDBOX" "git push")" none
assert_eq "unbalanced quotes silent" "$(hook "$SANDBOX" "git push 'oops")" none

out=$(printf 'not json' | python3 "$HOOK"); rc=$?
assert_eq "malformed payload exits 0" "$rc" 0
assert_eq "malformed payload prints nothing" "$out" ""
out=$(printf '' | python3 "$HOOK"); rc=$?
assert_eq "empty payload exits 0" "$rc" 0
out=$(printf '{"tool_name":"Write","tool_input":{"content":"git push --force"}}' | python3 "$HOOK")
assert_eq "other tools ignored" "$out" ""
finish
