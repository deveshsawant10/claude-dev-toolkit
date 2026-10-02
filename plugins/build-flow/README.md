# build-flow

Take an idea all the way to merged code, in three steps, each one a skill:

```
idea ──/req-gathering──▶ brief ──/build-plan──▶ GitHub issues ──/execute-build──▶ merged PRs
                       docs/idea-<name>.md    epics · stories · tasks       TDD · subagents · board
```

| Step | Skill | Input | Output |
|------|-------|-------|--------|
| 1 | `/req-gathering` | A raw idea | A requirements brief, built from structured multiple-choice questions, saved to `docs/idea-<name>.md` |
| 2 | `/build-plan` | The brief | Epics (milestones), stories and tasks as GitHub issues, with labels, dependencies (`Blocked by: #N`) and parallel batches |
| 3 | `/execute-build` | The open task issues | A Todo → Doing → Done project board; each task built test-first by a subagent in its own worktree and merged through a PR |

Every decision point is a multiple-choice question with a recommended option. Nothing is written to GitHub before you approve it.

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install build-flow@claude-dev-toolkit
```

## Requirements

- [`gh`](https://cli.github.com), authenticated (`gh auth login`) with the `repo` scope. Add the `project` scope (`gh auth refresh -s project`) so `/execute-build` can manage the project board.
- Python 3 for `build-status`.
- Optional: `graphify`. When it is present, `/execute-build` refreshes the code graph; otherwise that step is skipped.

## `build-status`

A read-only progress report for the issues `/build-plan` created. Once the plugin is installed it is on your `PATH`, and it is also available as the `/build-status` command:

```
$ build-status --repo acme/widgets
repo=acme/widgets
epic   open=1 closed=0
story  open=1 closed=0
task   open=3 closed=1  progress=25%

ready now (1):
  #4 Task 1.1.2: Session API [parallel-safe]

waiting (2):
  #5 Task 1.1.3: Logout <- #4
  #6 Task 1.1.4: Audit log <- blocked label
```

A task is **ready** when every `Blocked by: #N` in its body points to a closed issue and it has no `blocked` label.

| Flag | Meaning |
|------|---------|
| `--repo OWNER/NAME` | Repository to read. Defaults to the current directory's repo. |
| `--milestone NAME` | Only count one epic, e.g. `"Epic 1: Auth"`. |
| `--json` | Machine-readable output. |

Exit codes: `0` ok, `2` bad usage, `3` gh missing, not authenticated, or failed.

## Layout

```
build-flow/
├── .claude-plugin/plugin.json
├── skills/
│   ├── req-gathering/SKILL.md
│   ├── build-plan/SKILL.md
│   └── execute-build/SKILL.md
├── commands/build-status.md     # /build-status
├── bin/build-status             # PATH shim → scripts/build_status.py
├── scripts/build_status.py      # stdlib-only Python
└── tests/                       # run: tests/run  (uses a fake gh, no network)
```

## License

MIT
