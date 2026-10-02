---
name: review-loop
description: "Use when a pull request has review comments to address: lists unresolved review threads, evaluates each comment on its technical merits, fixes what is right, replies with reasoning where it is not, runs tests, pushes, replies to each thread with the commit, and resolves only the threads actually fixed. Triggers on \"address the review comments\", \"fix the PR feedback\", \"reply to the reviewers\", \"go through the review on #123\", or after a reviewer requests changes."
---

# review-loop

Work through review feedback on a pull request until no unresolved threads remain or the user stops.

Two commands are on PATH once this plugin is installed:

| Command | Effect |
|---|---|
| `pr-comments [PR] [--repo R] [--all] [--json]` | **Read-only.** Unresolved review threads with their thread id, `file:line`, `outdated` flag and every comment |
| `pr-reply <thread-id> --body-file F [--resolve]` | **Public write.** Posts a reply in that thread; `--resolve` also marks it resolved |

Exit codes: `0` ok, `2` bad usage, `3` gh missing, not authenticated or API error, `4` no pull request found.

## Process

### 1. Find the PR and its threads
Run `pr-comments` with no PR number to use the current branch's PR. If it exits 4, ask the user for the PR number. Make sure the local branch is the PR's branch (`branch=` in the header) and is up to date: `git fetch` and compare with the remote branch before changing anything.

### 2. Judge each thread before touching code
For every unresolved thread, read the comment **and the code it points to**, then put it in one of three buckets:

- **Agree.** The comment is correct. Plan a fix.
- **Disagree.** The comment is wrong, out of scope, or conflicts with another requirement. Plan a reply that explains why, with evidence (a test, a doc, a code path). Do not change code just to make a comment go away.
- **Unclear.** Plan a reply with a specific question.

`outdated` threads point at code that has since changed. Check whether the concern still applies to the current code before acting.

Show the user the full list (thread, bucket, one-line plan) and let them override any bucket before you start.

### 3. Fix
- One small commit per thread, or per group of threads about the same thing. Use Conventional Commits and put the reviewer's point in the subject, e.g. `fix(auth): mask session token in logs`.
- Run the project's tests and linter after the fixes. Do not push red.

### 4. Push (ask first)
Ask the user before the first push. Before every push, `git fetch` and confirm the branch is not behind its remote. If it is, rebase or merge first and re-run the tests. Never force-push unless the user asks for it.

### 5. Reply (ask first)
Draft a reply for every thread and **show all drafts to the user before posting the first one**. After they approve, post with `pr-reply`, writing each body to a temp file first:

- **Fixed:** what changed and the commit short sha, e.g. "Masked the token before logging. Fixed in `abc1234`." Then `--resolve`.
- **Disagreed:** the reasoning. Do **not** resolve. The reviewer decides.
- **Question:** the question. Do not resolve.

Only resolve threads whose fix is pushed. Resolving a thread you did not fix hides the reviewer's concern.

### 6. Check CI and loop
Run `gh pr checks <PR>`. If a check fails because of your change, fix it as in step 3. Then run `pr-comments` again: reviewers may have replied. Repeat until `unresolved=0` or the user says stop.

## Rules

- Replies are public and carry the user's name. Keep them short, factual and polite. No apologies, no filler.
- Never paste secrets, internal URLs or customer data into a reply.
- Never resolve a thread just to clear the list.
- If `pr-reply` fails partway, run `pr-comments` to see what was posted before retrying, so nothing is posted twice.
