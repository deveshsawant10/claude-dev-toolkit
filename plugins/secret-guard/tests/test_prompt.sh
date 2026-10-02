#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

t=$(fake github)
assert_eq "prompt with a GitHub token is blocked" "$(prompt "gh auth refresh -h github.com -s project, $t")" block
assert_contains "reason names the type" "$(last_output)" "GitHub token"
assert_contains "reason says to revoke" "$(last_output)" "revoke or rotate"
assert_not_contains "reason never echoes the token" "$(last_output)" "${t:4}"
assert_eq "exit code 0" "$(last_rc)" 0

for k in github-oauth github-pat aws-id aws-secret private-key slack stripe google anthropic; do
  v=$(fake "$k")
  assert_eq "prompt with $k blocked" "$(prompt "here you go: $v")" block
  assert_not_contains "$k value not echoed" "$(last_output)" "${v: -12}"
done

assert_eq "normal prompt passes" "$(prompt "push the branch and open a PR")" none
assert_eq "talking about tokens passes" "$(prompt "use \$GITHUB_TOKEN from the env, starts with ghp_")" none
assert_eq "AWS documentation key passes" "$(prompt "e.g. $(fake aws-doc)")" none
assert_eq "low-entropy fake passes" "$(prompt "$(fake low-entropy)")" none
assert_eq "redacted value passes" "$(prompt "token=ghp_***REDACTED***")" none
assert_eq "key header without a body passes" "$(prompt "it starts with -----BEGIN OPENSSH PRIVATE KEY-----")" none
finish
