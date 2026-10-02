#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

out=$(AWS_STUB_ONLINE_IDS=$'i-0aaaaaaaaaaaaaaa1\ti-0ccccccccccccccc3' "$BIN/ssm-ls" 2>&1); rc=$?
assert_eq "exits 0" "$rc" 0
assert_contains "online instance marked" "$out" $'i-0aaaaaaaaaaaaaaa1\trunning\tonline\t10.0.0.11\t2026-10-01T10:00:00\tBuild instance for core'
assert_contains "offline instance marked" "$out" $'i-0bbbbbbbbbbbbbbb2\trunning\toffline'
assert_eq "newest launch first" "$(printf '%s\n' "$out" | head -1 | cut -f1)" "i-0bbbbbbbbbbbbbbb2"
assert_contains "running filter by default" "$(calls | grep describe-instances)" "Name=instance-state-name,Values=running"

"$BIN/ssm-ls" --name "Build instance" >/dev/null 2>&1
assert_contains "--name becomes a tag filter" "$(calls | grep describe-instances | tail -1)" "Name=tag:Name,Values=*Build instance*"

"$BIN/ssm-ls" --all >/dev/null 2>&1
assert_not_contains "--all drops the state filter" "$(calls | grep describe-instances | tail -1)" "instance-state-name"

empty="$SANDBOX/empty.txt"; : >"$empty"
out=$(AWS_STUB_INSTANCES=$empty "$BIN/ssm-ls" 2>&1)
assert_contains "no instances message" "$out" "no matching instances"

out=$(AWS_STUB_EC2=denied "$BIN/ssm-ls" 2>&1); rc=$?
assert_eq "describe denied exits 3" "$rc" 3

out=$("$BIN/ssm-ls" --bogus 2>&1); rc=$?
assert_eq "unknown flag exits 2" "$rc" 2

finish
