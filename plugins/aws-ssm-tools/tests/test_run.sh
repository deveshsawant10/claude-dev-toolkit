#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

out=$("$BIN/ssm-run" "$ID" -- echo hello 2>&1); rc=$?
assert_eq "success exits 0" "$rc" 0
assert_contains "prints remote stdout" "$out" "hello"
assert_contains "uses AWS-RunShellScript" "$(calls)" "--document-name AWS-RunShellScript"

# shellcheck disable=SC2016 # the $(( )) must expand remotely, not here.
out=$("$BIN/ssm-run" "$ID" -- 'echo "a b" | tr a-z A-Z; echo "$((2+3))" '"'"'q'"'"'' 2>&1)
assert_contains "quotes survive the trip" "$out" "A B"
assert_contains "remote shell expansion works" "$out" "5"

"$BIN/ssm-run" "$ID" -- 'echo oops >&2; exit 7' >"$SANDBOX/o" 2>"$SANDBOX/e"; rc=$?
assert_eq "remote exit code passes through" "$rc" 7
assert_contains "remote stderr goes to stderr" "$(cat "$SANDBOX/e")" "oops"

out=$("$BIN/ssm-run" "$ID" -- 'echo token=ghp_abcdefghijklmnopqrstuvwxyz0123456789; echo key AKIAABCDEFGHIJKLMNOP; echo password: hunter2' 2>&1)
assert_contains "github token redacted" "$out" "token=ghp_***REDACTED***"
assert_not_contains "github token value hidden" "$out" "abcdefghijklmnop"
assert_contains "aws key id redacted" "$out" "AKIA***REDACTED***"
assert_not_contains "password hidden" "$out" "hunter2"

out=$("$BIN/ssm-run" "$ID" -- echo bare ghp_abcdefghijklmnopqrstuvwxyz0123456789 2>&1)
assert_contains "bare github token keeps its prefix" "$out" "bare ghp_***REDACTED***"
out=$("$BIN/ssm-run" "$ID" --no-redact -- echo ghp_abcdefghijklmnopqrstuvwxyz0123456789 2>&1)
assert_contains "--no-redact shows the raw value" "$out" "ghp_abcdefghijklmnopqrstuvwxyz0123456789"

printf 'echo from-file\n' >"$SANDBOX/s.sh"
out=$("$BIN/ssm-run" "$ID" --file "$SANDBOX/s.sh" 2>&1)
assert_contains "--file runs a local script" "$out" "from-file"

out=$(AWS_STUB_INPROGRESS_POLLS=3 "$BIN/ssm-run" "$ID" -- echo waited 2>&1); rc=$?
assert_eq "waits through InProgress" "$rc" 0
assert_contains "output after waiting" "$out" "waited"

out=$(AWS_STUB_INPROGRESS_POLLS=999999 SSM_POLL_SECONDS=1 "$BIN/ssm-run" "$ID" --timeout 2 -- true 2>&1); rc=$?
assert_eq "timeout exits 4" "$rc" 4
assert_contains "timeout message" "$out" "timed out"

out=$(AWS_STUB_FINAL_STATUS=Cancelled "$BIN/ssm-run" "$ID" -- true 2>&1); rc=$?
assert_eq "non-Success status with rc 0 still fails" "$rc" 1
assert_contains "names the status" "$out" "Cancelled"

out=$("$BIN/ssm-run" "$ID" --profile prod --region ap-south-1 -- true 2>&1)
assert_contains "passes profile and region" "$(calls | tail -1)" "--profile prod --region ap-south-1"

out=$(AWS_STUB_PING=ConnectionLost "$BIN/ssm-run" "$ID" -- true 2>&1); rc=$?
assert_eq "offline instance exits 4" "$rc" 4
assert_contains "offline message" "$out" "not Online"

out=$(AWS_STUB_AUTH=expired "$BIN/ssm-run" "$ID" --profile prod -- true 2>&1); rc=$?
assert_eq "expired credentials exit 3" "$rc" 3
assert_contains "sso hint names the profile" "$out" "aws sso login --profile prod"

out=$("$BIN/ssm-run" not-an-id -- true 2>&1); rc=$?
assert_eq "bad instance id exits 2" "$rc" 2
out=$("$BIN/ssm-run" "$ID" 2>&1); rc=$?
assert_eq "missing command exits 2" "$rc" 2
out=$("$BIN/ssm-run" "$ID" --timeout abc -- true 2>&1); rc=$?
assert_eq "bad timeout exits 2" "$rc" 2

finish
