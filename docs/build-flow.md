# build-flow: design notes

## Why three skills instead of one

Each step has a different input and a natural stopping point: you may gather requirements without planning yet, or plan without building yet. Separate skills let you stop, review, and resume. Each skill ends by offering the next one.

## The hand-off contract

| From → To | Contract |
|-----------|----------|
| `req-gathering` → `build-plan` | The brief is a markdown file at `docs/idea-<name>.md` with fixed sections (Problem, Scope v1, Success criteria, …). |
| `build-plan` → `execute-build` | GitHub issues labelled `epic` / `story` / `task`. Task bodies carry `Part of #N`, `Blocked by: #N`, a files-touched list and `- [ ]` acceptance criteria. |
| `execute-build` → `build-status` | Issue state plus the `blocked` and `parallel-safe` labels. |

Changing one of these formats means updating both sides of it.

## Why `build-status` is a script

Counting issues and resolving `Blocked by` edges is deterministic, so it should not be left to the model to work out from a long issue list. A script gives the same answer every time, can be tested offline against a fake `gh`, and is cheap to run between batches.

It is stdlib-only Python so that it needs nothing beyond `gh` and the Python 3 that already ships with Linux and macOS (no `jq`).
