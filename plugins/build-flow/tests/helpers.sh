#!/usr/bin/env bash
# Shared assertions. Each test file sources this, runs, then calls finish.
# shellcheck disable=SC2034 # read by the sourcing test files.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin/build-status"
export PATH="$HERE/stub:$PATH"
export GH_STUB_ISSUES="$HERE/fixtures/issues.json"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

assert_contains() { # name haystack needle
  case $2 in *"$3"*) ok "$1" ;; *) bad "$1" "expected to contain: $3"$'\n'"got: $2" ;; esac
}
assert_not_contains() {
  case $2 in *"$3"*) bad "$1" "expected NOT to contain: $3"$'\n'"got: $2" ;; *) ok "$1" ;; esac
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $3"$'\n'"got: $2"; fi
}
finish() { printf '  %d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
