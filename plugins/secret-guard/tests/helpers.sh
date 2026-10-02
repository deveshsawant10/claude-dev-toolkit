#!/usr/bin/env bash
# Shared setup and assertions for secret-guard tests.
# shellcheck disable=SC2034 # read by the sourcing test files.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$HERE/../hooks/secret_guard.py"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/repo/.git"
REPO="$SANDBOX/repo"
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
assert_not_contains() {
  case $2 in *"$3"*) bad "$1" "expected NOT to contain the value" ;; *) ok "$1" ;; esac
}

fake() { python3 "$HERE/fakes.py" "$1"; }

# tool <tool_name> <tool_input-json>  -> prints decision ("deny" or "none")
# prompt <text>                       -> prints decision ("block" or "none")
# Full hook output is saved for last_output; exit code for last_rc.
run_hook() { # mode payload
  printf '%s' "$2" | python3 "$HOOK" "$1" >"$SANDBOX/last"
  echo $? >"$SANDBOX/rc"
}
tool() {
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[3],"tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$1" "$2" "$REPO")
  run_hook tool "$payload"
  if [ ! -s "$SANDBOX/last" ]; then echo none; return; fi
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])' <"$SANDBOX/last"
}
prompt() {
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"UserPromptSubmit","cwd":sys.argv[2],"prompt":sys.argv[1]}))' "$1" "$REPO")
  run_hook prompt "$payload"
  if [ ! -s "$SANDBOX/last" ]; then echo none; return; fi
  python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' <"$SANDBOX/last"
}
# json-encode a string argument
js() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
last_output() { cat "$SANDBOX/last"; }
last_rc() { cat "$SANDBOX/rc"; }
finish() { printf '  %d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
