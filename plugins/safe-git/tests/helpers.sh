#!/usr/bin/env bash
# Shared setup and assertions. Every test gets throwaway repos and a fake HOME.
# shellcheck disable=SC2034 # read by the sourcing test files.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$HERE/../hooks/check_push.py"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global advice.detachedHead false
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $3"$'\n'"got: $2"; fi
}
assert_contains() {
  case $2 in *"$3"*) ok "$1" ;; *) bad "$1" "expected to contain: $3"$'\n'"got: $2" ;; esac
}

# hook <cwd> <command> -> prints the decision ("deny"/"ask"/"none"). It runs in
# a $(...) subshell, so the full output and exit code go to files: read them
# with last_output / last_rc.
hook() {
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2")
  printf '%s' "$payload" | python3 "$HOOK" >"$SANDBOX/last"
  echo $? >"$SANDBOX/rc"
  if [ ! -s "$SANDBOX/last" ]; then echo none; return; fi
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' <"$SANDBOX/last"
}
last_output() { cat "$SANDBOX/last"; }
last_rc() { cat "$SANDBOX/rc"; }

# A bare "remote" plus two clones (a = ours, b = a teammate), both on main,
# with a feature branch "feat" pushed.
make_repos() {
  git init -q --bare "$SANDBOX/remote.git"
  git clone -q "$SANDBOX/remote.git" "$SANDBOX/a" 2>/dev/null
  (cd "$SANDBOX/a" && echo 1 >f && git add f && git commit -qm one && git push -q origin main 2>/dev/null \
    && git checkout -qb feat && echo 2 >g && git add g && git commit -qm two && git push -q -u origin feat 2>/dev/null)
  git clone -q "$SANDBOX/remote.git" "$SANDBOX/b" 2>/dev/null
  (cd "$SANDBOX/b" && git checkout -q feat)
}

finish() { printf '  %d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
