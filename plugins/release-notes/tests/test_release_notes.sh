#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"
make_repo
cd "$REPO" || exit 1

out=$("$BIN/release-notes" v1.0.0 v1.1.0 --offline 2>&1); rc=$?
assert_eq "explicit range exits 0" "$rc" 0
assert_contains "titled by TO tag" "$out" "## v1.1.0 (2026-10-02)"
assert_contains "summary names FROM" "$out" "_9 changes since v1.0.0_"
assert_not_contains "FROM commit excluded" "$out" "first release"
assert_contains "breaking section" "$out" "### ⚠ Breaking changes"
assert_contains "breaking item with scope and PR" "$out" "- **api:** drop v1 endpoints (#12)"
assert_contains "breaking footer shown" "$out" "  - clients must call /v2"
assert_contains "feature with scope" "$out" "- **auth:** add SSO login (#10)"
assert_contains "fix" "$out" "- handle empty config ("
assert_contains "perf group" "$out" "### Performance"
assert_contains "refactor group" "$out" "### Refactoring"
assert_contains "docs group" "$out" "### Documentation"
assert_contains "chore in maintenance" "$out" "- **deps:** bump requests"
assert_contains "non-conventional in other" "$out" "### Other changes"
order=$(printf '%s\n' "$out" | grep '^### ' | tr '\n' '|')
assert_eq "section order" "$order" "### ⚠ Breaking changes|### Features|### Bug fixes|### Performance|### Refactoring|### Documentation|### Maintenance|### Other changes|"
assert_eq "breaking not repeated under features" "$(printf '%s\n' "$out" | grep -c 'drop v1 endpoints')" 1
assert_not_contains "PR suffix stripped from text" "$out" "endpoints (#12) (#12)"

out=$("$BIN/release-notes" --offline 2>&1)
assert_contains "default TO is Unreleased" "$out" "## Unreleased"
assert_contains "default FROM is newest tag" "$out" "since v1.1.0"
assert_contains "merge PR uses PR title" "$out" "- **ui:** align the save button (#15)"
assert_not_contains "branch commit not listed (first-parent)" "$out" "button alignment"
assert_not_contains "branch-sync merge skipped" "$out" "Merge branch"
assert_contains "squash PR mapped" "$out" "dark mode (#16)"

out=$("$BIN/release-notes" --to v1.1.0 --offline 2>&1)
assert_contains "without a pattern the nearest tag of any family wins" "$out" "since lib--v0.1.0"
out=$("$BIN/release-notes" --to v1.1.0 --tag-pattern 'v*' --offline 2>&1)
assert_contains "--to tag compares with previous tag" "$out" "since v1.0.0"
assert_contains "--to tag titles the section" "$out" "## v1.1.0"
out=$("$BIN/release-notes" v1.0.0 --offline 2>&1)
assert_contains "single argument is FROM" "$out" "## Unreleased"
assert_contains "single argument FROM used" "$out" "since v1.0.0"
out=$("$BIN/release-notes" --tag-pattern 'lib--v*' --offline 2>&1)
assert_contains "tag pattern picks matching family" "$out" "since lib--v0.1.0"
out=$("$BIN/release-notes" --to v1.0.0 --offline 2>&1)
assert_contains "first tag has no previous: from first commit" "$out" "from the first commit"

out=$("$BIN/release-notes" v1.1.0 v1.1.0 --offline 2>&1); rc=$?
assert_eq "empty range exits 0" "$rc" 0
assert_contains "empty range says so" "$out" "No changes."

: >"$GH_STUB_LOG"
out=$("$BIN/release-notes" v1.0.0 v1.1.0 2>&1)
assert_contains "gh adds author" "$out" "by @alice"
assert_contains "gh repo gives PR links" "$out" "([#12](https://github.com/acme/widgets/pull/12))"
assert_contains "queried each PR" "$(cat "$GH_STUB_LOG")" "pr view 10 --repo acme/widgets"
out=$("$BIN/release-notes" v1.0.0 v1.1.0 --repo o/r 2>&1)
assert_contains "--repo used for links" "$out" "https://github.com/o/r/pull/10"

: >"$GH_STUB_LOG"
out=$("$BIN/release-notes" v1.0.0 v1.1.0 --offline 2>&1)
assert_eq "--offline never calls gh" "$(cat "$GH_STUB_LOG")" ""
out=$(GH_STUB_AUTH=no "$BIN/release-notes" v1.0.0 v1.1.0 2>&1); rc=$?
assert_eq "unauthenticated gh still works" "$rc" 0
assert_not_contains "no author without gh" "$out" "by @"

mini="$SANDBOX/minbin"; mkdir -p "$mini"
for t in bash dirname git python3; do ln -s "$(command -v "$t")" "$mini/$t"; done
out=$(PATH="$mini" "$BIN/release-notes" v1.0.0 v1.1.0 2>&1); rc=$?
assert_eq "works with gh absent" "$rc" 0
assert_contains "plain PR refs without gh" "$out" "drop v1 endpoints (#12)"

out=$("$BIN/release-notes" v1.0.0 v1.1.0 --offline --json 2>&1)
assert_eq "json count" "$(printf '%s' "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" 9
assert_eq "json breaking flag" "$(printf '%s' "$out" | python3 -c 'import json,sys;print([c["pr"] for c in json.load(sys.stdin)["commits"] if c["breaking"]])')" "[12]"

out=$("$BIN/release-notes" nope --offline 2>&1); rc=$?
assert_eq "unknown ref exits 3" "$rc" 3
assert_contains "names the ref" "$out" "unknown ref: nope"
out=$("$BIN/release-notes" v1.0.0 v1.1.0 --to v1.1.0 --offline 2>&1); rc=$?
assert_eq "TO twice exits 2" "$rc" 2
out=$("$BIN/release-notes" --repo 'bad repo' 2>&1); rc=$?
assert_eq "bad --repo exits 2" "$rc" 2
out=$(cd "$SANDBOX" && "$BIN/release-notes" --offline 2>&1); rc=$?
assert_eq "outside a repo exits 3" "$rc" 3

finish
