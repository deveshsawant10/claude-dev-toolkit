#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"
make_repos
A="$SANDBOX/a" B="$SANDBOX/b"

assert_eq "up to date: silent" "$(hook "$A" "git push")" none

(cd "$A" && echo 3 >h && git add h && git commit -qm three)
assert_eq "ahead only: silent" "$(hook "$A" "git push")" none

(cd "$B" && echo x >x && git add x && git commit -qm teammate && git push -q origin feat 2>/dev/null)
assert_eq "diverged from remote: denied" "$(hook "$A" "git push")" deny
assert_contains "reason names the branch" "$(last_output)" "'feat' is behind 'origin/feat'"
assert_contains "reason gives the fix" "$(last_output)" "git pull --rebase origin feat"
assert_eq "explicit remote and branch: denied" "$(hook "$A" "git push origin feat")" deny
assert_eq "git -C from another dir: denied" "$(hook "$SANDBOX" "git -C a push")" deny
assert_eq "cd then push: denied" "$(hook "$SANDBOX" "cd a && git push")" deny
assert_eq "refreshes origin/feat like a normal fetch" "$(cd "$A" && git rev-parse origin/feat)" "$(cd "$B" && git rev-parse feat)"
assert_eq "leaves no private ref behind" "$(cd "$A" && git for-each-ref refs/safe-git | wc -l | tr -d ' ')" 0

(cd "$A" && git pull -q --rebase origin feat 2>/dev/null)
assert_eq "after pull --rebase: silent" "$(hook "$A" "git push")" none

(cd "$A" && git checkout -qb brand-new)
assert_eq "new branch not on remote: silent" "$(hook "$A" "git push -u origin brand-new")" none

(cd "$A" && git remote set-url origin "$SANDBOX/missing.git")
assert_eq "unreachable remote: fail open" "$(hook "$A" "git push origin feat")" none
finish
