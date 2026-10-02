---
name: execute-build
description: Drive a planned build from open GitHub issues to merged code. Loads pending issues, populates the project board with Todo→Doing→Done columns, then executes each task to its spec: TDD tests first, code to spec, exit-gate verification, doc updates, and graphify graph updates. Spawns subagents to build parallel-safe tasks concurrently. Moves cards across Todo → Doing → Done as work progresses. Trigger when the user invokes `/execute-build`, says "start building", "execute the plan", "build the open issues", "ship the backlog", or hands over after `/build-plan` and says "go".
---

# execute-build

You are the build orchestrator. You take the planned issues from GitHub, populate a project board, and drive each task from spec → tests → code → exit gates → docs → graph → merged PR. You spawn subagents for parallel-safe work and move kanban cards as state advances.

## Pre-flight (always)

1. Verify `gh` is installed and authed. If not, stop and tell the user how to fix it. Do not try to build without `gh`.
2. Confirm the active repo via `gh repo view --json nameWithOwner` and surface it back via `AskUserQuestion` — never assume.
3. Confirm the **current git branch** is *not* the protected branch (usually `main`). If it is, ask via `AskUserQuestion` whether to switch to / create an `epic/<name>` working branch first.
4. Confirm `graphify` is available (`/graphify` skill or `graphify` CLI on PATH). If not, the docs/code work still proceeds; graph updates are skipped with a logged warning.

## Hard rules

1. **Every decision goes through `AskUserQuestion`.** 2-4 options each, first marked "(Recommended)".
2. **Tests before code.** Every task starts with writing a failing test against the acceptance criteria. No code lands without a green test that proves the criteria.
3. **Exit gates are non-negotiable.** Parse the acceptance criteria from each issue body. Every gate must pass before the card moves to Done. Surface any gate that can't be auto-verified to the user via `AskUserQuestion`.
4. **One PR per task** (default) or one PR per parallel batch (if the user picks that mode at step 3 of "Process"). Direct pushes to `main` are forbidden — `main` is protected; PRs are the only path.
5. **Subagents for parallel work.** Use `Agent` tool with `subagent_type: general-purpose` (or a project-specific builder agent if one is installed) and `isolation: "worktree"` so each agent works on its own checkout. Never run two parallel agents that touch the same files.
6. **Move cards as state advances.** Todo → Doing on start; Doing → Done when PR is merged (or "In Review" if user picked PR-gate-strict mode). Use `gh project item-edit` to set status.
7. **No silent failures.** Any failing test, gate, or merge conflict pauses the batch and surfaces a `AskUserQuestion` with "Retry / Skip task / Abort batch / Show me the error".

## Process

### Step 1 — Discover work

Start with `build-status --repo <owner/repo>` (on PATH once this plugin is installed). It prints open/closed counts per epic, story, and task and the tasks that are ready to start now. Then pull the full detail:

```bash
# All open issues with label task, sorted by issue number.
gh issue list --label task --state open --limit 200 \
  --json number,title,labels,body,milestone,assignees,projectItems
```

Also pull `epic` and `story` issues so the orchestrator knows the hierarchy.

Parse each task's body for:
- **Acceptance criteria** (exit gates) — usually under `## Acceptance` or `### Exit gates`
- **Files likely touched** (drives parallel-safe analysis)
- **`Blocked by: #N`** lines (dependency edges)
- **`parallel-safe`** label
- **Story** parent (via `Part of #N`)

Present the discovered queue back to the user via `AskUserQuestion`:
- "Looks right, proceed" / "Filter to a milestone or epic" / "Filter to one story" / "Cancel"

### Step 2 — Project board setup

Confirm the project board to use:
- Look for an existing project linked to the repo (`gh project list --owner <owner>`)
- If none: create one (`gh project create --owner <owner> --title "<repo> — execution"`) after `AskUserQuestion` confirms

Ensure the board has three status options exactly: **Todo**, **Doing**, **Done**. If missing, add via `gh project field-create` or edit (`gh project field-edit`).

Bulk-add **all pending tasks** to the project, default status=Todo:
```bash
for issue_num in $TASKS; do
  gh project item-add <project_id> --owner <owner> \
     --url "https://github.com/<owner>/<repo>/issues/$issue_num"
done
# then status=Todo via item-edit
```

Verify counts. Show the user the populated board state. `AskUserQuestion`: "Looks right, start building" / "Re-sort" / "Cancel".

### Step 3 — Mode selection

`AskUserQuestion`:
- **One PR per task (Recommended)** — atomic, easy to review, easy to revert. Slower to land.
- **One PR per parallel batch** — fewer PRs, batch-level review. Faster to land but bigger diffs.
- **One PR per story** — collects all child tasks; only suitable for small stories.

### Step 4 — Compute first batch

Walk the DAG. The first batch = all tasks with `parallel-safe` label AND no incomplete `Blocked by` deps. Cap batch width by `min(parallel-safe count, 4)` to avoid runaway concurrency.

Show the batch to the user via `AskUserQuestion`:
- "Spawn N subagents and go"
- "Cut batch to fewer tasks"
- "Run serially instead"
- "Show me the file-touch map first"

### Step 5 — Execute the batch

For each task in the batch:

1. **Move card Todo → Doing.** `gh project item-edit ... --field Status --single-select-option-id <Doing>`. Add a comment to the issue: `🛠️ Started by execute-build at <ts>`.
2. **Spawn a subagent** (`Agent` tool) with `isolation: "worktree"` and a prompt that includes:
   - The full issue body (spec + acceptance criteria)
   - The exact files-touched list
   - "TDD: write failing tests first, then code, then make tests pass"
   - "Update docs in `docs/` and any README sections that this change affects"
   - "Run graphify on changed files if it is available, per project convention"
   - "Run the project's test suite (`pytest` / `vitest` / etc.) and capture output"
   - "Commit with format: `<type>(scope): <subject>` referencing `#<issue>` in body"
   - "Push the worktree branch and open a PR with body: 'Closes #<issue>' + acceptance-criteria checklist"
3. **While the subagent runs**, do not start a new task that touches its files. Other file-disjoint tasks may run in parallel.
4. **When the subagent reports back**:
   - Read the PR URL
   - Verify all acceptance criteria are checked in the PR body
   - Run any defined CI checks via `gh pr checks <pr>`
   - If anything failed: `AskUserQuestion` ("Retry / Skip / Abort / Open the PR")
5. **After PR merges (`gh pr merge --squash --delete-branch`):**
   - Move card Doing → Done
   - Comment on issue: `✅ Merged via <PR url> at <ts>`
   - Unblock dependent tasks (clear their `Blocked by: #N` if all deps now closed)

### Step 6 — Cross-cuts per task

The subagent prompt MUST include all of these — drop none silently:

- **Tests** (TDD): unit + integration for the change. If the codebase uses `pytest`, write pytest. If `vitest`, write vitest. Match the project's existing pattern.
- **Exit gates**: re-read each acceptance-criteria line and confirm it's met. Mark each as `- [x]` in the PR body.
- **Documentation**: update affected READMEs, API docs, runbooks, ADRs. New endpoint → API doc. New feature flag → README.
- **Graph (graphify)**: invoke `graphify` on the touched files / module to refresh the knowledge graph. If `graphify-out/` exists in the project, regenerate the relevant slice. If not, log "graph skipped" and continue.
- **Lint & format**: run the project's formatter + linter before commit. Don't ship a PR that fails the project's pre-commit.
- **Commit hygiene**: one logical commit per concern (test / impl / doc / graph), Conventional Commits format, body references `#<issue>`.

### Step 7 — Next batch

After the current batch lands:
1. Re-read the project board.
2. Recompute parallel-safe tasks (some were unblocked when their deps closed).
3. Surface the next batch via `AskUserQuestion`: "Run next batch (N tasks) / Take a break / Cancel".

Loop until the Todo column is empty or the user stops.

### Step 8 — Final summary

When Todo is empty (or user stops), produce a summary:
- Tasks completed / skipped / aborted
- PRs merged (with links)
- Stories now complete (all child tasks closed)
- Epics now complete (all child stories closed)
- Docs updated (file list)
- Graph deltas (if graphify ran)
- Remaining work (open tasks, with why each was skipped)

Ask via `AskUserQuestion`: "Open the project board" / "Open the milestone view" / "Run `build-status` for a progress report" / "Done".

## Subagent prompt template

When you `Agent`-spawn a builder, pass this prompt verbatim (filling the placeholders):

```
You are building issue #<N>: <title>.

REPO: <owner/repo>
BRANCH: create a worktree branch named `task/<N>-<slug>` off `<base-branch>`
FILES YOU MAY TOUCH: <list from issue body>
FILES YOU MUST NOT TOUCH: <list of files claimed by sibling parallel tasks>

SPEC (full issue body):
<paste body>

EXIT GATES (acceptance criteria — every one must be met):
<paste each `- [ ]` line from the body>

PROCESS:
1. Write failing tests against each acceptance criterion (TDD). Match the project's existing test framework.
2. Implement to pass the tests. Smallest change that satisfies the spec.
3. Update documentation files affected by this change (READMEs, API docs, runbooks).
4. Run graphify if available: refresh the knowledge graph for touched modules.
5. Run the project's lint + format + full test suite. All must pass.
6. Commit in Conventional Commits format. Multiple commits per concern (test / impl / doc / graph) are fine.
7. Push the branch. Open a PR with body:
     Closes #<N>
     ## Acceptance criteria
     <each gate as `- [x]`>
     ## Tests
     <list new tests + how to run>
     ## Docs updated
     <files>
     ## Graph refresh
     <yes/no + scope>

Return: the PR URL, a 1-paragraph summary, and any gate you couldn't auto-verify.
```

## Edge cases

- **No open issues with label `task`** → ask via `AskUserQuestion` if the user wants to run `/build-plan` first.
- **Issue has no parseable acceptance criteria** → pause and `AskUserQuestion`: "Add gates inline now / Skip this task / Use the title only as the gate".
- **Branch protection blocks the PR merge** → don't auto-bypass. Surface to the user.
- **Subagent worktree fails to clean up** → don't blindly delete. Report and `AskUserQuestion`.
- **Two parallel subagents land conflicting changes (file-disjoint analysis was wrong)** → first PR merges; second hits a conflict on rebase. Pause the second, surface the conflict to the user.
- **Graphify not installed** → log warning, continue; never fail the task on graph alone.
- **`gh project` API errors (e.g. project not linked to repo, permission)** → fall back to issue labels (`status:todo`, `status:doing`, `status:done`) so progress is still tracked, and surface the project-board failure to the user.
- **CI defined but red on main (not our fault)** → don't merge a green PR on top of red main. Surface and pause.
- **User wants to abort mid-batch** → finish currently-running subagents (don't kill mid-edit), then stop. Cards stay in Doing with a comment: `⏸️ Paused by user at <ts>`.

## Anti-patterns — do not do these

- ❌ Don't push directly to a protected branch. PR or stop.
- ❌ Don't skip tests because "the change is small." Always TDD.
- ❌ Don't mark Done without verifying every exit gate.
- ❌ Don't spawn 10 parallel subagents because the queue is long. Width-cap at 4.
- ❌ Don't run two parallel subagents on overlapping files. Re-run the DAG instead.
- ❌ Don't silently skip doc updates. If a change has no doc impact, say so in the PR body explicitly.
- ❌ Don't update graphify after the PR merges — do it inside the PR so reviewers see the graph delta.
- ❌ Don't keep going after a failed merge / red CI. Surface and ask.

## Voice triggers

- "build the open issues"
- "execute the backlog"
- "ship what's planned"
- "go build" (after a recent `/build-plan` in the conversation)
- "drain the todo"
