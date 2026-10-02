# release-notes

Draft release notes from git history. It groups the commits between two tags by Conventional Commit type, puts breaking changes first, and links PRs. Claude then rewrites the draft into readable notes and, only when you say so, prepends them to `CHANGELOG.md` or creates a **draft** GitHub release.

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install release-notes@claude-dev-toolkit
```

Then ask Claude "write release notes since v1.2.0".

## Requirements

- `git` and Python 3.
- Optional: [`gh`](https://cli.github.com), logged in, for PR authors, labels and links. Without it everything still works offline.

## Command

```bash
release-notes                        # newest tag before HEAD → HEAD
release-notes v1.2.0 v1.3.0          # FROM (exclusive) → TO (inclusive)
release-notes --to v1.3.0            # one release: FROM = the tag before it
release-notes v1.2.0                 # one argument is FROM: v1.2.0 → HEAD
release-notes --tag-pattern 'v*'     # pick FROM only from matching tags
release-notes --repo owner/name      # PR links for this repo
release-notes --offline              # never call gh
release-notes --json                 # structured output
```

Example:

```
## v1.3.0 (2026-10-02)

_5 changes since v1.2.0_

### ⚠ Breaking changes

- **api:** drop v1 endpoints (#12) by @alice (a1b2c3d)
  - clients must call /v2

### Features

- **auth:** add SSO login (#10) by @bob (d4e5f6a)

### Bug fixes

- handle empty config (e7f8a9b)
```

## How it reads history

- **Range.** It uses `git log --first-parent FROM..TO`, which lists the commits that landed on the release branch. A merged PR appears once, not once per branch commit.
- **Default FROM.** If you don't give FROM, it uses the newest tag before TO. If TO is itself a tag, FROM is the previous one. If there are no tags, it starts from the first commit.
- **PR numbers** come from squash subjects (`feat: x (#12)`) and merge subjects (`Merge pull request #12 from …`, using the PR title from the body). Other `Merge …` commits are skipped.
- **Groups.** `feat`, `fix`, `perf`, `refactor` and `docs` each get their own section. `chore`, `ci`, `build`, `test`, `style` and `revert` go under Maintenance. Everything else goes under Other.
- **Breaking changes** are either `type!:` or a `BREAKING CHANGE:` footer. The footer text is shown under the item.

Exit codes: `0` ok · `2` bad usage · `3` not a git repository or unknown ref.

## Tests

```bash
tests/run   # builds throwaway git repos, fake gh, no network, plus shellcheck
```
