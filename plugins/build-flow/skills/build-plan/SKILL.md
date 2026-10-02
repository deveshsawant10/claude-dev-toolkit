---
name: build-plan
description: "Take a detailed requirements brief and turn it into a full implementation plan — epics, stories, tasks — applying software best practices (testing, observability, security, error handling, accessibility, docs, rollback). Identifies which tasks can run in parallel so subagents can be deployed effectively. Creates GitHub issues with proper labels, milestones, and dependency links via `gh`. Trigger when the user invokes `/build-plan`, says \"create an implementation plan\", \"break this into epics and stories\", \"plan the build\", \"create issues for this\", or hands over a requirements brief and asks \"how do we build this?\"."
---

# build-plan

You are turning a finalized requirements brief into a concrete, parallelizable implementation plan and (with user approval) the GitHub issues to track it.

## Inputs

Look for inputs in this order:
1. A requirements brief in the current conversation (e.g. from `/req-gathering`).
2. A markdown file the user references (e.g. `docs/idea-<name>.md`).
3. The user's prose description right now.

If the input is thin or vague, **do not invent details**. Use `AskUserQuestion` to fill the gaps before planning. Treat anything beyond what the brief says as a hypothesis to confirm, not a fact.

## Hard rules

1. **Plan before creating.** Show the full epic/story/task tree first. Get explicit user approval (via `AskUserQuestion`) before any `gh issue create` call.
2. **Every question goes through `AskUserQuestion`.** 2-4 options each, first one marked "(Recommended)" with a one-line rationale.
3. **No issues created without a repo confirmation.** Verify the active GitHub repo (`gh repo view --json nameWithOwner`) and confirm via AskUserQuestion before any writes.
4. **Apply best practices as cross-cutting concerns** (next section). Don't just plan happy-path features.
5. **Mark parallel-safe work explicitly.** A task is parallel-safe if it has no incomplete dependencies AND touches files no other in-flight task touches.
6. **Estimate scope, not time.** Use S / M / L (S = ~hours, M = ~day, L = ~multi-day). Skip hour estimates — they lie.

## Best-practices cross-cuts (apply per epic)

For every epic, ask: which of these need stories of their own, or task-level work?

- **Tests**: unit + integration + e2e. Aim for coverage on the magic moment.
- **Error handling & failure modes**: every external call, every user input.
- **Observability**: logs / metrics / traces. Structured, queryable.
- **Security**: authn, authz, input validation, secret handling, dep vulns.
- **Performance**: known hot paths, expected load, n+1 risks.
- **Accessibility (if UI)**: keyboard nav, ARIA, color contrast.
- **Data**: migrations, backups, schema versioning, idempotency.
- **Documentation**: README, API docs, runbook for ops, ADRs for big calls.
- **Rollback / feature flag**: how to disable cleanly if it goes sideways.
- **CI/CD**: build, test, lint, deploy gates.

Skip a cut only if you can justify it ("no UI" → skip a11y).

## The plan structure

```
EPIC <N>: <Name>             — milestone
├── STORY <N.M>: <Name>      — issue, label: story
│   ├── TASK <N.M.K>: <name> — sub-issue (or checklist if sub-issues unavailable),
│   │                          label: task, parallel-safe? Y/N
│   └── TASK ...
├── STORY ...
DEPENDENCIES:
  STORY 1.2 → blocks STORY 2.1
  TASK 1.3.2 → blocks TASK 2.1.1
PARALLEL BATCHES:
  Batch A (run together): TASK 1.1.1, TASK 1.1.2, TASK 1.2.1
  Batch B (after A):     TASK 1.3.1, TASK 2.1.1
  Batch C: ...
```

The **PARALLEL BATCHES** section is the payoff — that's what tells you which subagents can be spawned together.

## Process

### 1. Read inputs, confirm understanding
Briefly summarize what you understood from the brief (3-5 bullets). Ask the user via `AskUserQuestion` if anything is wrong or missing before continuing.

### 2. Decompose into epics
An epic = one user-visible capability that ships independently. Aim for 3–7 epics for a v1.

Show the epic list with one-line goal + estimated size. Ask via `AskUserQuestion` to confirm / merge / split / cut.

### 3. Per-epic: stories + best-practice cross-cuts
For each epic, draft stories (3–8 per epic typical) plus the cross-cuts that need their own work. A story = a vertical slice that delivers value or unblocks the next slice.

### 4. Per-story: tasks
A task = a unit of work a single contributor (human or subagent) can finish in one sitting. Each task names the files it'll touch.

### 5. Dependency analysis
For each task, list its inputs (files, services, prior tasks). Build the DAG. Mark tasks as `parallel-safe` when they're root-of-DAG (no incomplete deps) and file-disjoint from other roots.

### 6. Compute parallel batches
Walk the DAG topologically. Tasks at the same "depth" with no file conflicts form a batch. Surface the batches explicitly.

### 7. Present the plan
Output the full tree (markdown) with:
- The epic/story/task hierarchy
- Dependency edges
- Parallel batches
- Best-practice coverage map (which cross-cut each epic addresses)
- A one-page summary at the top: total epics / stories / tasks, longest critical path, biggest parallel batch

### 8. Approval gate
`AskUserQuestion`:
- "Create all GitHub issues now"
- "Create epics + stories only (skip tasks)"
- "Save plan to `docs/build-plan-<name>.md` only — no issues yet"
- "Iterate on a specific section"

### 9. Create issues (only if user approved)
Order: epics → stories → tasks. After each create, capture the issue number for use in cross-links.

- **Epic** → `gh issue create --milestone "Epic N: <Name>"` (create milestone first if missing) + label `epic`. Body has the goal, success criteria, story checklist with placeholders.
- **Story** → `gh issue create --label story --milestone "Epic N"`. Body has acceptance criteria, files-likely-touched, task checklist with placeholders.
- **Task** → If repo has sub-issues enabled, create as sub-issue of the story; else create as plain issue with `--label task` and link back: "Part of #<story>". Body includes files touched, parallel-safe flag, dependencies (`Blocks: #X` / `Blocked by: #Y`).
- After all issues exist, **update epic and story bodies** to replace the placeholder checklists with real `- [ ] #N` references — so the GitHub UI shows live progress.

Use `--repo <owner>/<name>` on every `gh` call (don't rely on cwd).

### 10. Hand off
Print a final summary:
- Total issues created
- The first parallel batch with explicit "spawn subagents for these N tasks in parallel" instruction
- Link to the milestone view: `https://github.com/<owner>/<repo>/milestones`
- Next step: run `/execute-build` to start building Batch A, or `build-status` to see the queue

## Labels to ensure exist

Before creating issues, ensure these labels exist (`gh label create --force`):
- `epic` — colour: purple
- `story` — colour: blue
- `task` — colour: green
- `parallel-safe` — colour: yellow
- `blocked` — colour: red
- one per cross-cut: `tests`, `security`, `observability`, `a11y`, `perf`, `docs`, `infra`, `ci-cd`

## Edge cases

- **No `gh` installed or not authed** → say so, fall back to producing the plan as a markdown file at `docs/build-plan-<name>.md`. Show the user how to install/auth `gh` after.
- **Wrong repo** → never assume. Always confirm `nameWithOwner` via `AskUserQuestion`.
- **Existing issues with same titles** → ask via `AskUserQuestion`: "Skip (use existing) / Append timestamp / Cancel".
- **Plan is huge (>50 tasks)** → propose chunking: ship Epic 1 as a vertical slice first, plan Epic 2+ when Epic 1 lands. Confirm via `AskUserQuestion`.
- **User changes scope mid-plan** → back up to step 2; don't try to patch the tree in place.

## Anti-patterns — do not do these

- ❌ Don't create issues before the user approves the full plan.
- ❌ Don't estimate hours. Use S/M/L.
- ❌ Don't write code. This skill plans, it doesn't implement.
- ❌ Don't invent constraints the brief didn't specify. Ask.
- ❌ Don't mark something parallel-safe if it touches the same files as another in-flight task. File conflicts are not "merge conflicts you can resolve later" — they're guaranteed rework.
- ❌ Don't skip the cross-cuts (tests, security, etc.) to make the plan look smaller.
- ❌ Don't dump 80 issues at once with no parallel-batch guidance. The whole point is structured concurrency.

## Output: parallel-batch handoff format

When listing the first parallel batch (the one ready to run *now*), use this format so the user / subagent orchestrator can act on it directly:

```
PARALLEL BATCH A — spawn subagents for these tasks together:
  • #<issue>  TASK 1.1.1  <name>      files: src/foo/a.py, src/foo/b.py
  • #<issue>  TASK 1.1.2  <name>      files: web/components/x.tsx
  • #<issue>  TASK 1.2.1  <name>      files: docs/architecture.md

After Batch A lands, Batch B unblocks:
  • #<issue>  TASK 1.3.1  ...
  • #<issue>  TASK 2.1.1  ...
```
