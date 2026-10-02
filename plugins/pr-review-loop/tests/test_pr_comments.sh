#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

out=$("$BIN/pr-comments" 2>&1); rc=$?
assert_eq "exits 0" "$rc" 0
assert_contains "header names PR and repo" "$out" "pr=#42 repo=acme/widgets state=OPEN branch=42-login"
assert_contains "counts across pages" "$out" "unresolved=2 total=3"
assert_contains "thread id and location" "$out" "[1] PRRT_one  src/auth.py:17"
assert_contains "first comment" "$out" "@alice: This leaks the session token in logs."
assert_contains "multi-line body kept" "$out" "      Please mask it."
assert_contains "reply in thread" "$out" "@bob: Agreed"
assert_contains "link to thread" "$out" "https://github.com/acme/widgets/pull/42#discussion_r1"
assert_contains "second page fetched" "$out" "[2] PRRT_three  src/old.py:9  (outdated)"
assert_contains "deleted author shown as ghost" "$out" "@ghost: Why not reuse helper()?"
assert_not_contains "resolved hidden by default" "$out" "PRRT_two"
assert_contains "paginates with cursor" "$(ghlog)" "cursor=CUR1"
assert_contains "number sent as typed field" "$(ghlog)" "number=42"

out=$("$BIN/pr-comments" --all 2>&1)
assert_contains "--all includes resolved" "$out" "PRRT_two  README.md:3  (resolved)"

out=$("$BIN/pr-comments" 7 --repo other/repo 2>&1)
assert_contains "explicit PR and repo used" "$(ghlog)" "number=7"
assert_contains "explicit owner" "$(ghlog)" "owner=other"

out=$("$BIN/pr-comments" --json 2>&1)
assert_eq "json unresolved count" "$(printf '%s' "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["unresolved"])')" 2
assert_eq "json thread ids" "$(printf '%s' "$out" | python3 -c 'import json,sys;print(",".join(t["id"] for t in json.load(sys.stdin)["threads"]))')" "PRRT_one,PRRT_three"

out=$(GH_STUB_NO_PR=1 "$BIN/pr-comments" 2>&1); rc=$?
assert_eq "no PR for branch exits 4" "$rc" 4
assert_contains "no PR hint" "$out" "pass a PR number"

out=$(GH_STUB_NOT_FOUND=1 "$BIN/pr-comments" 999 2>&1); rc=$?
assert_eq "missing PR exits 4" "$rc" 4

out=$(GH_STUB_AUTH=no "$BIN/pr-comments" 2>&1); rc=$?
assert_eq "unauthenticated exits 3" "$rc" 3
assert_contains "auth hint" "$out" "gh auth login"

out=$(GH_STUB_API_FAIL=1 "$BIN/pr-comments" 2>&1); rc=$?
assert_eq "API failure exits 3" "$rc" 3
assert_contains "API error surfaced" "$out" "HTTP 502"

out=$("$BIN/pr-comments" --repo 'not a repo' 2>&1); rc=$?
assert_eq "bad --repo exits 2" "$rc" 2
out=$("$BIN/pr-comments" abc 2>&1); rc=$?
assert_eq "non-numeric PR exits 2" "$rc" 2

finish
