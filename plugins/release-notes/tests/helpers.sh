#!/usr/bin/env bash
# Shared setup: a throwaway git repo with tagged, conventional history.
# shellcheck disable=SC2034 # read by the sourcing test files.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="$HERE/../bin"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export PATH="$HERE/stub:$PATH"
export GH_STUB_LOG="$SANDBOX/gh.log"
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_DATE=2026-10-02T10:00:00Z GIT_COMMITTER_DATE=2026-10-02T10:00:00Z
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0
fail=0

REPO="$SANDBOX/repo"
c() { git -C "$REPO" commit -q --allow-empty -m "$1" ${2:+-m "$2"}; }
make_repo() {
  git init -q -b main "$REPO"
  c "feat: first release"
  git -C "$REPO" tag v1.0.0
  c "feat(auth): add SSO login (#10)"
  c "fix: handle empty config"
  c "feat(api)!: drop v1 endpoints (#12)" "BREAKING CHANGE: clients must call /v2"
  c "docs: explain SSO setup"
  git -C "$REPO" tag lib--v0.1.0
  c "chore(deps): bump requests"
  c "ci: cache pip"
  c "perf: faster startup"
  c "refactor(core): split module"
  c "Tidy up whitespace"
  git -C "$REPO" tag v1.1.0
  git -C "$REPO" checkout -q -b topic
  c "fix(ui): button alignment"
  git -C "$REPO" checkout -q main
  git -C "$REPO" merge -q --no-ff topic -m "Merge pull request #15 from acme/topic" -m "fix(ui): align the save button"
  git -C "$REPO" merge -q --no-ff topic -m "Merge branch 'main' into topic" 2>/dev/null || true
  c "feat: dark mode (#16)"
}

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
finish() { printf '  %d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
