#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal $(...) is the point: it must reach GitHub unexpanded.
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

printf 'Fixed in abc1234: token is masked.\n@here "quotes" and $(not expanded)\n' >"$SANDBOX/body.md"

out=$("$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/body.md" 2>&1); rc=$?
assert_eq "reply exits 0" "$rc" 0
assert_contains "prints new comment url" "$out" "replied: https://github.com/acme/widgets/pull/42#discussion_r99"
assert_contains "sends the thread id" "$(ghlog)" "threadId=PRRT_one"
assert_contains "sends body verbatim" "$(ghlog)" 'body=Fixed in abc1234: token is masked.'
assert_contains "body special characters intact" "$(ghlog)" '@here "quotes" and $(not expanded)'
assert_not_contains "no resolve without --resolve" "$(ghlog)" "resolveReviewThread"

: >"$GH_STUB_LOG"
out=$("$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/body.md" --resolve 2>&1); rc=$?
assert_eq "reply+resolve exits 0" "$rc" 0
assert_contains "reports resolved" "$out" "resolved: PRRT_one"
assert_contains "resolve mutation sent" "$(ghlog)" "resolveReviewThread"

out=$(printf 'from stdin\n' | "$BIN/pr-reply" PRRT_one --body-file - 2>&1); rc=$?
assert_eq "stdin body works" "$rc" 0
assert_contains "stdin body sent" "$(ghlog)" "body=from stdin"

out=$(GH_STUB_RESOLVE_FAIL=1 "$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/body.md" --resolve 2>&1); rc=$?
assert_eq "resolve error exits 3" "$rc" 3
assert_contains "resolve error message" "$out" "Resource not accessible"

: >"$SANDBOX/empty.md"
out=$("$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/empty.md" 2>&1); rc=$?
assert_eq "empty body exits 2" "$rc" 2
: >"$GH_STUB_LOG"
out=$("$BIN/pr-reply" PRRT_one 2>&1); rc=$?
assert_eq "missing --body-file exits 2" "$rc" 2
out=$("$BIN/pr-reply" 'PRRT_x;rm' --body-file "$SANDBOX/body.md" 2>&1); rc=$?
assert_eq "bad thread id exits 2" "$rc" 2
out=$("$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/nope.md" 2>&1); rc=$?
assert_eq "unreadable body file exits 2" "$rc" 2
assert_eq "nothing posted on usage errors" "$(ghlog)" ""

out=$(GH_STUB_AUTH=no "$BIN/pr-reply" PRRT_one --body-file "$SANDBOX/body.md" 2>&1); rc=$?
assert_eq "unauthenticated exits 3" "$rc" 3

finish
