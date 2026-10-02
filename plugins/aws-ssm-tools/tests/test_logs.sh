#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

# "Remote" log files live in the sandbox; the tool sends absolute paths.
logs="$SANDBOX/var/toe"
mkdir -p "$logs/TOE_old" "$logs/TOE_new"
seq 1 50 | sed 's/^/old line /' >"$logs/TOE_old/console.log"
touch -t 202601010000 "$logs/TOE_old/console.log"
{ seq 1 300 | sed 's/^/new line /'; echo "ERROR connectors.zip missing token=ghp_abcdefghijklmnopqrstuvwxyz0123"; } >"$logs/TOE_new/console.log"

out=$("$BIN/ssm-logs" "$ID" "$logs/TOE_*/console.log" 2>&1); rc=$?
assert_eq "exits 0" "$rc" 0
assert_contains "picks the newest file" "$out" "==> $logs/TOE_new/console.log"
assert_not_contains "ignores older file" "$out" "old line"
assert_eq "default 200 lines plus header" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 201

out=$("$BIN/ssm-logs" "$ID" "$logs/TOE_*/console.log" --lines 5 2>&1)
assert_eq "--lines limits output" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 6

out=$("$BIN/ssm-logs" "$ID" "$logs/TOE_*/console.log" --grep 'ERROR|FATAL' 2>&1)
assert_contains "--grep finds the match" "$out" "ERROR connectors.zip missing"
assert_not_contains "--grep drops other lines" "$out" "new line 1"
assert_contains "log secrets redacted" "$out" "token=ghp_***REDACTED***"
assert_not_contains "log secret value hidden" "$out" "abcdefghijklmnop"

out=$("$BIN/ssm-logs" "$ID" "$logs/TOE_*/console.log" --grep "it's \$(rm -rf x)" 2>&1); rc=$?
assert_eq "hostile grep pattern is just a pattern" "$rc" 0

out=$("$BIN/ssm-logs" "$ID" "$logs/TOE_*/console.log" --list 2>&1)
assert_contains "--list shows files" "$out" "TOE_old/console.log"
assert_eq "--list is newest first" "$(printf '%s\n' "$out" | head -1)" "$logs/TOE_new/console.log"

out=$("$BIN/ssm-logs" "$ID" "$logs/nothing-*.log" 2>&1); rc=$?
assert_eq "no match exits non-zero" "$rc" 1
assert_contains "no match message" "$out" "no file matches"

out=$("$BIN/ssm-logs" "$ID" 'relative/path.log' 2>&1); rc=$?
assert_eq "relative path rejected" "$rc" 2
out=$("$BIN/ssm-logs" "$ID" '/tmp/x;rm -rf /' 2>&1); rc=$?
assert_eq "shell metacharacters in path rejected" "$rc" 2
out=$("$BIN/ssm-logs" "$ID" "$logs/x.log" --lines 0 2>&1); rc=$?
assert_eq "zero lines rejected" "$rc" 2

finish
