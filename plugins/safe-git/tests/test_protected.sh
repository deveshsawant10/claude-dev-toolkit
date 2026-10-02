#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"
make_repos
A="$SANDBOX/a"

(cd "$A" && git checkout -q main && echo m >m && git add m && git commit -qm m)
assert_eq "push from main asks" "$(hook "$A" "git push")" ask
assert_contains "reason names the branch" "$(last_output)" "protected branch 'main'"
(cd "$A" && git checkout -q feat)
assert_eq "HEAD:main asks" "$(hook "$A" "git push origin HEAD:main")" ask
assert_eq "feat:refs/heads/main asks" "$(hook "$A" "git push origin feat:refs/heads/main")" ask
assert_eq "feature branch silent" "$(hook "$A" "git push origin feat")" none
assert_eq "delete protected asks" "$(hook "$A" "git push origin --delete main")" ask
assert_eq "delete feature silent" "$(hook "$A" "git push origin --delete feat")" none
assert_eq "master is protected by default" "$(hook "$A" "git push origin feat:master")" ask

mkdir -p "$A/.claude"
printf '{"protectedBranches": ["release"]}\n' >"$A/.claude/safe-git.json"
assert_eq "config replaces defaults: main now silent" "$(hook "$A" "git push origin HEAD:main")" none
assert_eq "config: release asks" "$(hook "$A" "git push origin HEAD:release")" ask
printf 'not json' >"$A/.claude/safe-git.json"
assert_eq "broken config falls back to defaults" "$(hook "$A" "git push origin HEAD:main")" ask
finish
