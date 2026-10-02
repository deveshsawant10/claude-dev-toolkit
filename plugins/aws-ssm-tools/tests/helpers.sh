#!/usr/bin/env bash
# Shared setup and assertions. Every test runs in a throwaway HOME.
# shellcheck disable=SC2034 # read by the sourcing test files.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export FAKE_REMOTE_HOME="$SANDBOX/remote"
export AWS_STUB_STATE="$SANDBOX/aws"
export AWS_STUB_FAKEBIN="$HERE/fakebin"
export AWS_STUB_INSTANCES="$HERE/fixtures/instances.txt"
export SSM_POLL_SECONDS=0
export PATH="$HERE/stub:$PATH"
mkdir -p "$HOME" "$FAKE_REMOTE_HOME" "$AWS_STUB_STATE"
ID=i-0aaaaaaaaaaaaaaa1
# Token-shaped test values are assembled at runtime so the repository never
# contains a string that looks like a real credential.
FAKE_GHP="ghp_""abcdefghijklmnopqrstuvwxyz0123456789"
FAKE_AKIA="AKIA""ABCDEFGHIJKLMNOP"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
assert_contains() {
  case $2 in *"$3"*) ok "$1" ;; *) bad "$1" "expected to contain: $3"$'\n'"got: $2" ;; esac
}
assert_not_contains() {
  case $2 in *"$3"*) bad "$1" "expected NOT to contain: $3"$'\n'"got: $2" ;; *) ok "$1" ;; esac
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $3"$'\n'"got: $2"; fi
}
calls() { cat "$AWS_STUB_STATE/calls" 2>/dev/null; }
finish() { printf '  %d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
