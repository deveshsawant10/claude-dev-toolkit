#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

t=$(fake github)
body=$'line one\nline two\nGH_TOKEN='"$t"$'\n'
assert_eq "Write with a token denied" "$(tool Write "{\"file_path\":\"/r/.env\",\"content\":$(js "$body")}")" deny
assert_contains "reason names file and line" "$(last_output)" "/r/.env (content): GitHub token (line 3)"
assert_not_contains "reason never echoes the token" "$(last_output)" "${t:4}"
assert_contains "reason suggests env vars" "$(last_output)" "environment variable"

a=$(fake aws-id)
assert_eq "Edit with an AWS key denied" "$(tool Edit "{\"file_path\":\"/r/c.py\",\"old_string\":\"x\",\"new_string\":$(js "KEY = '$a'")}")" deny
assert_contains "Edit reason names the type" "$(last_output)" "AWS access key id"

assert_eq "Edit removing a token (old_string only) allowed" "$(tool Edit "{\"file_path\":\"/r/c.py\",\"old_string\":$(js "$t"),\"new_string\":\"os.environ['GH_TOKEN']\"}")" none

pk=$(fake private-key)
assert_eq "MultiEdit with a private key denied" "$(tool MultiEdit "{\"file_path\":\"/r/k\",\"edits\":[{\"old_string\":\"a\",\"new_string\":\"b\"},{\"old_string\":\"c\",\"new_string\":$(js "$pk")}]}")" deny
assert_contains "MultiEdit names the edit" "$(last_output)" "(edit 2): private key"

s=$(fake slack)
assert_eq "NotebookEdit with a Slack token denied" "$(tool NotebookEdit "{\"notebook_path\":\"/r/n.ipynb\",\"new_source\":$(js "token = '$s'")}")" deny

assert_eq "Bash with a token denied" "$(tool Bash "{\"command\":$(js "curl -H 'Authorization: token $t' https://api.github.com/user")}")" deny
assert_contains "Bash reason names the command" "$(last_output)" "the shell command"

# shellcheck disable=SC2016 # $GH_TOKEN must stay literal: it is the command text.
assert_eq "Bash using an env var allowed" "$(tool Bash '{"command":"curl -H \"Authorization: token $GH_TOKEN\" https://api.github.com/user"}')" none
assert_eq "ordinary Write allowed" "$(tool Write '{"file_path":"/r/a.py","content":"print(\"hello\")\n"}')" none
assert_eq "Read is never inspected" "$(tool Read '{"file_path":"/r/.env"}')" none

# Allowlist: a regex in .secret-guard-allow at the repo root lets one value through.
printf '# test fixture\n%s\n' "${a:0:8}" >"$REPO/.secret-guard-allow"
assert_eq "allowlisted value passes" "$(tool Write "{\"file_path\":\"/r/t.txt\",\"content\":$(js "$a")}")" none
assert_eq "non-allowlisted value still denied" "$(tool Write "{\"file_path\":\"/r/t.txt\",\"content\":$(js "$t")}")" deny
mkdir -p "$REPO/sub/dir"
out=$(python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"tool_name":"Write","tool_input":{"file_path":"x","content":sys.argv[2]}}))' "$REPO/sub/dir" "$a" | python3 "$HOOK" tool)
assert_eq "allowlist found from a subdirectory" "$out" ""
printf '([unclosed\n' >"$REPO/.secret-guard-allow"
assert_eq "broken allowlist regex is ignored, not fatal" "$(tool Write "{\"file_path\":\"/r/t.txt\",\"content\":$(js "$a")}")" deny
rm -f "$REPO/.secret-guard-allow"

out=$(printf 'not json' | python3 "$HOOK" tool); rc=$?
assert_eq "malformed payload exits 0" "$rc" 0
assert_eq "malformed payload prints nothing" "$out" ""
out=$(printf '[]' | python3 "$HOOK" prompt); rc=$?
assert_eq "non-object payload exits 0" "$rc" 0
finish
