---
name: release-notes
description: "Use when preparing a release or changelog: collects the commits between two tags (default: the latest tag to HEAD), groups them by Conventional Commit type with breaking changes first, rewrites them into human-friendly notes without inventing anything, and on explicit confirmation prepends them to CHANGELOG.md or creates a draft GitHub release. Triggers on \"write release notes\", \"what changed since v1.2\", \"update the changelog\", \"draft the release\"."
---

# release-notes

One command is on PATH once this plugin is installed:

```bash
release-notes                         # newest tag → HEAD
release-notes v1.2.0 v1.3.0           # explicit range (FROM exclusive, TO inclusive)
release-notes --to v1.3.0             # notes for an existing tag: FROM = the tag before it
release-notes --tag-pattern 'v*'      # ignore other tag families when picking FROM
release-notes --json                  # structured, for your own processing
release-notes --offline               # never call gh
```

It is read-only. It reads `git log --first-parent`, so each merged PR appears once. It groups changes into Breaking, Features, Bug fixes, Performance, Refactoring, Documentation, Maintenance and Other, and adds PR links, labels and authors when `gh` is logged in.

Exit codes: `0` ok, `2` bad usage, `3` not a git repo or unknown ref.

## Process

1. **Pick the range.** If the user named both versions, pass them. For notes about one existing release, use `--to <tag>`: a single positional argument is FROM, not TO. Otherwise run with no arguments and tell the user which FROM tag was chosen (it is in the summary line). If the repo has several tag families (e.g. `app--v*` and `lib--v*`), ask which one and pass `--tag-pattern`.
2. **Generate.** Run `release-notes --json` so you have every commit's type, scope, PR, labels and breaking note.
3. **Rewrite for humans.** Turn the raw list into notes a user of the project would read:
   - Keep the section order, with breaking changes first, and explain what a user must do for each breaking change.
   - Merge commits that describe one change; drop pure noise (typo fixes, CI tweaks) into a short "Maintenance" line or leave it out.
   - Keep PR links and authors.
   - **Do not invent anything.** Every sentence must trace back to a commit or PR in the output. If a commit message is too vague to describe, quote it rather than guess.
4. **Show the draft** to the user and ask what to do with it:
   - Prepend to `CHANGELOG.md`
   - Create a **draft** GitHub release
   - Nothing (they will copy it)
5. **Only after an explicit yes:**
   - **CHANGELOG.md:** insert the new section directly below the top `# Changelog` heading, or at the top of the file if there is no heading. Create the file if it does not exist. Never rewrite existing sections.
   - **Draft release:** write the notes to a temp file, then `gh release create <TO-tag> --draft --title "<TO-tag>" --notes-file <file>`. Always `--draft`, so a person publishes it. If TO is `HEAD` (no tag yet), ask which tag to create instead of guessing.

## Rules

- Never publish a non-draft release, push tags, or commit the changelog unless the user asks for that specific action.
- If the range is empty, say so; do not produce an empty release.
- If most commits are not Conventional Commits, everything lands in "Other changes". Group them yourself by reading the subjects, and say that you did.
