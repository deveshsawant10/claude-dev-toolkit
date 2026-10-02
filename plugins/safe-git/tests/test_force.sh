#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"
make_repos
A="$SANDBOX/a"

assert_eq "--force denied" "$(hook "$A" "git push --force")" deny
assert_contains "reason suggests pull --rebase" "$(last_output)" "git pull --rebase"
assert_eq "-f denied" "$(hook "$A" "git push -f origin feat")" deny
assert_eq "combined -uf denied" "$(hook "$A" "git push -uf origin feat")" deny
assert_eq "+refspec denied" "$(hook "$A" "git push origin +feat")" deny
assert_eq "+src:dst denied" "$(hook "$A" "git push origin +HEAD:feat")" deny
assert_eq "--mirror denied" "$(hook "$A" "git push --mirror")" deny
assert_eq "--force=... form denied" "$(hook "$A" "git push --force origin feat")" deny
assert_eq "chained force denied" "$(hook "$A" "git add . && git commit -m x && git push --force")" deny
assert_eq "--force-with-lease allowed" "$(hook "$A" "git push --force-with-lease origin feat")" none
assert_eq "--force-if-includes allowed" "$(hook "$A" "git push --force-with-lease --force-if-includes")" none
assert_eq "force inside echo is not a push" "$(hook "$A" 'echo "git push --force"')" none
assert_eq "-o value is not a flag" "$(hook "$A" "git push -o ci.skip origin feat")" none
assert_eq "exit code always 0" "$(last_rc)" 0
finish
