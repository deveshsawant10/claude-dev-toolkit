# Skills guide

What each skill and command is for, how to call it, what it saves you, and what can go wrong. Each section is short enough to skim before you use the tool.

| Plugin | Skill / command | One line |
|---|---|---|
| build-flow | [`/req-gathering`](#req-gathering) | Raw idea → requirements brief |
| build-flow | [`/build-plan`](#build-plan) | Brief → epics, stories, tasks as GitHub issues |
| build-flow | [`/execute-build`](#execute-build) | Open task issues → merged PRs |
| build-flow | [`build-status`](#build-status) | How far along is the plan, and what can start now |
| aws-ssm-tools | [`ssm-ls`](#ssm-ls) | Find an instance and check SSM can reach it |
| aws-ssm-tools | [`ssm-run`](#ssm-run) | Run one command on an instance |
| aws-ssm-tools | [`ssm-logs`](#ssm-logs) | Read or grep the newest log file |
| aws-ssm-tools | [`ssm-port`](#ssm-port) | Reach a port on (or behind) an instance at localhost |
| aws-ssm-tools | [`ssm-ssh`](#ssm-ssh) | Temporary `ssh` / `scp` access, with optional auto-expiry |
| safe-git | [hook](#safe-git-1) | Blocks force pushes and stale pushes, asks before `main` |
| secret-guard | [hooks](#secret-guard-1) | Stops tokens entering the chat or being written to files |
| pr-review-loop | [`review-loop`](#review-loop) | Work through PR review threads end to end |
| release-notes | [`release-notes`](#release-notes-1) | Changelog from git history between tags |

In Claude Code, plugin skills are namespaced, e.g. `/build-flow:build-plan`. The short form `/build-plan` works too when no other skill has the same name. You can also just describe what you want ("plan this brief", "check the logs on i-0abc…") and the skill triggers by itself.

---

## build-flow

The three skills form a pipeline. Each can also be used on its own.

```
idea ──/req-gathering──▶ docs/idea-<name>.md ──/build-plan──▶ GitHub issues ──/execute-build──▶ merged PRs
                                                                    │
                                                              build-status
```

### req-gathering

**Use it when** you have an idea but not a spec: "I want a dashboard for X", "we should automate Y".

**How**
```
/req-gathering a stats page for customers showing ingestion volume
```
Claude asks 5–10 multiple-choice questions, the most important first (who is it for, what problem, v1 scope, …). Each question has a recommended option. At the end it writes a brief with fixed sections and offers to save it to `docs/idea-<name>.md` and go straight to `/build-plan`.

**What you get**
- A full brief in about 10 minutes instead of a long back-and-forth.
- Out-of-scope items and open risks are written down, so v1 doesn't quietly grow.
- The brief's format is exactly what `/build-plan` reads.

**What can go wrong**
- The brief can only be as good as your answers. Picking "Recommended" every time without reading gives a generic brief.
- It does not research anything. Facts about your systems come from you.
- For a one-line bug fix it is overkill. Skip it.

**Repeat task it replaces:** turning every new feature request into a requirements doc by hand, and the follow-up meetings caused by missing scope.

### build-plan

**Use it when** a brief is ready and you need the work broken down and tracked.

**How**
```
/build-plan docs/idea-customer-stats.md
```
1. Claude summarises the brief and asks you to confirm.
2. It proposes 3–7 epics, then stories and tasks for each. Every epic also covers tests, security, observability, docs and rollback.
3. It works out which tasks can run in parallel (no dependency, no shared files) and groups them into batches.
4. It shows you the whole tree. Nothing is created until you approve.
5. It confirms the repo, then creates labels, milestones (one per epic) and issues, with `Part of #N` and `Blocked by: #N` links.

**What you get**
- A plan you would otherwise spend half a day writing, with dependencies and parallel batches computed for you.
- Cross-cutting work such as tests and docs gets its own issues, so it isn't forgotten.
- Issues follow a fixed format, so `/execute-build` and `build-status` can read them.

**What can go wrong**
- **Big plans create many issues.** Above 50 tasks it suggests shipping Epic 1 first; take that advice. Deleting 100 issues is tedious.
- "Parallel-safe" is only as accurate as the files-touched list it guesses. Review it before relying on it.
- It needs `gh` logged in with write access to the repo. Without it, it can only save the plan to a markdown file.
- If you rerun it on the same brief, it asks about duplicate titles. Answer carefully or you get two sets of issues.

**Repeat task it replaces:** splitting work into tickets, labelling them, linking dependencies, and deciding who or what can work in parallel.

### execute-build

**Use it when** the issues exist and you want them built.

**How**
```
/execute-build
```
1. Pre-flight: checks `gh`, confirms the repo, and if you are on `main` asks to switch to a working branch first.
2. Loads open `task` issues and sets up a project board with Todo / Doing / Done.
3. You pick a PR mode: one PR per task (recommended), per batch, or per story.
4. For each batch (at most 4 tasks at once) it starts subagents in separate git worktrees. Each one writes failing tests first, then the code, updates docs, runs lint and tests, and opens a PR that says `Closes #N`.
5. It checks every acceptance criterion and CI result, merges, moves the card to Done, and unblocks dependent tasks.

**What you get**
- Planned work moves without you starting each task by hand.
- Tests come first, and every PR is tied to an issue with its acceptance criteria checked.
- Parallel work in separate worktrees, without agents editing the same files.
- The board always shows the real state.

**What can go wrong**
- **It costs the most tokens.** Each subagent is a full coding session; four in parallel cost about four times one.
- Subagents are only as good as the issue body. A vague task produces a vague PR.
- If the parallel-safe analysis is wrong, two PRs conflict. It pauses and asks rather than force-merging.
- It merges PRs. If your team requires human review, choose a stricter mode or keep branch protection on. It never bypasses branch protection.
- It needs the `project` scope on `gh` (`gh auth refresh -h github.com -s project`).

**Repeat task it replaces:** picking the next ticket, creating a branch, writing tests and code, opening a PR, moving the card, updating the parent issue, every time.

### build-status

**Use it when** you want to know where a plan stands or what can start right now. It is read-only and safe to run any time.

**How**
```bash
build-status                                   # current repo
build-status --repo owner/name --milestone "Epic 1: Auth"
build-status --json                            # for scripts
```
Or `/build-flow:build-status` inside Claude Code.

**What you get**
- Open and closed counts per epic, story and task, plus a progress percentage.
- **Ready now**: open tasks whose `Blocked by` issues are all closed. This is your next batch.
- **Waiting**: each blocked task with the issue it is waiting on.

**What can go wrong**
- It only understands the format `/build-plan` writes (`task` label, `Blocked by: #N`). Hand-made issues without those don't show up.
- It reads at most 1000 issues per call. Use `--milestone` on very large repos.

**Repeat task it replaces:** scrolling the issue list to work out what's unblocked.

#### Session start summary (hook)

**What it does:** when a Claude Code session starts, resumes, or is cleared or compacted in a repo that has `docs/idea-*.md` or `docs/build-plan-*.md`, build-flow runs `build-status` and gives Claude a short summary: progress, up to 5 ready tasks, and a pointer to `/execute-build`. Claude knows where the plan stands without being asked, and doesn't start building unless you say so.

**What can go wrong**
- It only runs in repos that have those docs files. Repos where you made the issues by hand get no summary.
- It needs `gh` logged in. If `gh` is missing, logged out, or slower than 8 seconds (`BUILD_FLOW_HOOK_TIMEOUT`), it stays silent and the session starts normally.
- To turn it off, disable the plugin's hooks in `/hooks`.

**Repeat task it replaces:** typing "where are we with the plan?" at the start of every session.

---

## aws-ssm-tools

All four commands work with an SSM-only role: no bastion, no port 22, no VPN. Every command accepts `--profile` and `--region`. Output is scanned for secrets (GitHub tokens, AWS keys, `password=`, `token=`), which are masked before you or Claude see them.

You can also just ask Claude, e.g. "why did the last Image Builder build fail", and the `ssm` skill picks the right command.

### ssm-ls

**Use it when** you know an instance by name or role, not by id, or you want to check SSM can reach it.

**How**
```bash
ssm-ls --name "Build instance" --region ap-south-1
ssm-ls --all            # include stopped instances
```

**What you get:** id, state, `online`/`offline` for SSM, private IP, launch time and Name tag, newest first. The build instance you need is usually the top row.

**What can go wrong**
- The `--name` match is case-sensitive.
- `offline` means SSM can't reach the instance: the agent is down, the IAM role is missing, or it is still booting. The other commands won't work on it.

**Repeat task it replaces:** opening the EC2 console, filtering, copying the instance id.

### ssm-run

**Use it when** you need one answer from a box: disk space, a process, a config value, a service status.

**How**
```bash
ssm-run i-0abc… -- 'df -h; systemctl status nginx --no-pager'
ssm-run i-0abc… --file ./collect-debug.sh --timeout 900
```

**What you get**
- Output in your terminal and the real remote exit code, so scripts and Claude can tell success from failure.
- Quotes, pipes and `$(…)` reach the remote shell unchanged, because the command is base64-encoded in transit.
- Secrets in output are masked.

**What can go wrong**
- **It runs as root.** A mistyped `rm` is a real `rm`. Claude is told to ask before running anything that changes state.
- Output is capped at 24,000 characters by SSM. It warns you when that happens.
- It is not interactive. `top`, `vim` or password prompts will hang until the timeout. Use `ssm-ssh` for those.
- Every command is recorded in the account's SSM command history, which is good for audit but visible to others.

**Repeat task it replaces:** Console → Session Manager → start session → type command → copy output → close.

### ssm-logs

**Use it when** the answer is in a log file, especially one with a changing name, like Image Builder's `TOE_<timestamp>/console.log`.

**How**
```bash
ssm-logs i-0abc… '/var/lib/amazon/toe/TOE_*/console.log' --grep 'ERROR|FAILED'
ssm-logs i-0abc… '/var/log/app/*.log' --lines 500
ssm-logs i-0abc… '/var/log/app/*.log' --list
```
Quote the glob so your own shell doesn't expand it.

**What you get**
- The newest matching file is chosen for you, and its name is printed first.
- `--grep` searches the whole file and returns only the last N matches, which keeps output small and inside the SSM limit.
- Tokens that appear in build logs (for example a `ghp_` PAT in a clone URL) are masked.

**What can go wrong**
- `--grep` is case-sensitive. Use `'error|Error|ERROR'` if you're unsure.
- An Image Builder step prints its output only when it finishes, so a running step looks silent.
- Paths must be absolute and can only contain normal filename characters. This is deliberate: the path is put into a remote shell command.

**Repeat task it replaces:** opening a session, `cd`-ing into the newest TOE folder, `tail` and `grep`, then copying the error out.

### ssm-port

**Use it when** you need a TCP service on the instance, or one the instance can reach, on your own machine: a web UI, an internal API, a database behind it such as RDS.

**How**
```bash
ssm-port i-0abc… 8080                                   # foreground, Ctrl-C to stop → http://localhost:8080
ssm-port i-0abc… 5432 --host mydb.xxxx.rds.amazonaws.com --local-port 15432 --background
ssm-port --list
ssm-port --stop 15432                                   # or: ssm-port --stop all
```

**What you get**
- `localhost:<port>` connected to the remote service, with no SSH key, no security group change and nothing written on the instance.
- `--host` reaches databases and services that only the instance can see.
- `--background` returns as soon as the port is actually listening and keeps a pid and log, so `--list` and `--stop` can manage it. `--stop` also ends the `session-manager-plugin` child process.

**What can go wrong**
- The local port defaults to the remote one, or 10000+port below 1024 (22 → 10022). If it's taken, the command fails; pick another with `--local-port`.
- A background forward keeps running until you `--stop` it or the SSM session times out. Check `ssm-port --list`.
- It needs `session-manager-plugin` installed locally. Your role needs `ssm:StartSession` and permission to use the port-forwarding documents.
- If the session dies before the port opens, it exits 4 and prints the session log (with secrets masked).

**Repeat task it replaces:** building long `aws ssm start-session --document-name AWS-StartPortForwardingSession… --parameters '{…}'` commands by hand and hunting down leftover tunnel processes.

### ssm-ssh

**Use it when** you need a real session: interactive debugging, `scp` files in or out, or port forwarding with `ssh -L`.

**How**
```bash
ssm-ssh i-0abc… --user ec2-user --profile prod --region ap-south-1
ssm-ssh i-0abc… --user ec2-user --ttl 2h  # key removes itself from the instance after 2h
ssh i-0abc…
scp ./patch.tar.gz i-0abc…:/tmp/
ssm-ssh --list                            # shows expires=… and marks EXPIRED keys
ssm-ssh --remove i-0abc…                  # when done
ssm-ssh --remove i-0abc… --local-only     # instance already gone
```

**What you get**
- Plain `ssh <instance-id>` and `scp` that work through SSM, with no key pairs to manage and no security group changes.
- A separate key per instance, tagged so that `--remove` deletes only that key and leaves other people's keys alone.
- Running it again is safe: it replaces the key and config instead of duplicating them.
- `--ttl 30m|2h|1d` (max 30d) schedules removal of the key on the instance itself, so forgotten access still ends. It uses a `systemd-run` timer, or a background job where systemd isn't available. Running setup again or `--remove` cancels the old timer.

**What can go wrong**
- **A pushed key is real access until it is removed.** Use `--ttl` unless you need the access to last, and run `--remove` when you're done; `--ttl` only cleans the instance, not your local key and config. Use `ssm-port` instead when you only need a TCP port.
- Without systemd, the `--ttl` timer is a background job, which a reboot of the instance cancels. `--remove` is the reliable cleanup.
- `--user` must exist on the instance (`ec2-user` on Amazon Linux, `ubuntu` on Ubuntu). If the user is wrong, the command fails and changes nothing.
- It needs `session-manager-plugin` installed locally.
- It edits `~/.ssh/config`, only inside its own marked block, placed at the top so it takes precedence over `Host *` rules.
- If the instance is replaced (for example by an autoscaling group), the new instance has a new id, so run setup again.

**Repeat task it replaces:** asking for a bastion or a port 22 rule, hunting for the right `.pem`, or typing long `aws ssm start-session` commands by hand.

---

## safe-git

A hook, so there is no command to run. Once it is installed, it checks every `git push` Claude runs through its Bash tool.

### safe-git

**Use it when** Claude pushes for you (for example during `/execute-build`) and you want to be sure it never force-pushes, never pushes from a stale branch, and never lands on `main` without asking.

**How**
Install it and keep working. To change the protected branches for one repo, add `.claude/safe-git.json`:
```json
{ "protectedBranches": ["main", "release"] }
```

**What you get**
- Force pushes (`--force`, `-f`, `+refspec`, `--mirror`) are blocked, and Claude is told to `git pull --rebase` instead. `--force-with-lease` is allowed.
- Before every push it runs `git fetch`. If the branch is behind or has diverged, the push is blocked and the reason gives the exact `git pull --rebase <remote> <branch>` to run. This is the "fetch before push" rule, applied automatically.
- A push or `--delete` aimed at `main`/`master` asks you first.
- It understands `git -C dir push`, `cd dir && git push`, chained commands and `HEAD:main`.

**What can go wrong**
- It only sees the command line. A push inside a script (`./deploy.sh`) or a git alias is not checked.
- It fails open: offline, unreachable remote, fetch timeout (8 s) or anything it can't parse means the push goes ahead with no message.
- Each push costs one extra fetch, usually under a second.
- It does not replace branch protection on GitHub. It only adds a check on your side.
- Tags count too: moving a tag such as `uat-ami` needs a force push, so safe-git blocks it. Run that push yourself in a terminal.

**Repeat task it replaces:** remembering to `git fetch` and compare before every push, and cleaning up after a force push that overwrote someone's commits.

---

## secret-guard

Hooks, so there is no command to run. They check your messages and everything Claude writes or runs.

### secret-guard

**Use it when** always. It costs nothing until it finds a secret.

**How**
Install it. For a known fake value in a test fixture, add a regex to `.secret-guard-allow` at the repo root, or better, build the fake at runtime from pieces.

**What you get**
- If you paste a token into a message, the message is **not sent** and you are told to revoke it. A token pasted into chat by mistake never reaches the conversation log.
- Claude can't write a GitHub, GitLab, AWS, Slack, Stripe, Google, Anthropic, OpenAI or npm token, or a private key, into a file, notebook or shell command. It is told to use an environment variable instead.
- Messages name the type and location (file, line, edit number) and never the value.

**What can go wrong**
- It checks input, not output. A secret printed by `cat .env` still reaches the conversation.
- It is pattern-based. A password with no recognisable prefix is not caught.
- A real-looking fake in a test file is blocked until you allowlist it or build it at runtime.
- It fails open on internal errors, so a broken Python install means no protection, silently.

**Repeat task it replaces:** scrubbing a leaked token from history and rotating it after the fact.

---

## pr-review-loop

### review-loop

**Use it when** a pull request has review comments to work through.

**How**
```
address the review comments on this PR
```
Or call the commands yourself:
```bash
pr-comments                      # unresolved threads on this branch's PR (read-only)
pr-comments 123 --repo o/r --all
pr-reply PRRT_kwDO… --body-file reply.md --resolve   # posts publicly
```
1. Claude lists every unresolved thread with its `file:line` and puts each in a bucket: agree (fix it), disagree (reply with reasoning), or unclear (ask a question). You can change any bucket.
2. It makes one small commit per fix and runs the tests.
3. It asks before the first push, and fetches before every push.
4. It shows all draft replies before posting any. Each reply names the fix commit.
5. It resolves only the threads that were actually fixed, then checks `gh pr checks` and loops until nothing is unresolved.

**What you get**
- No review comment is missed. Outdated threads are checked against the current code instead of being fixed blindly.
- Each reviewer gets a specific answer: what changed and in which commit, or why not.
- Threads are resolved only when the fix is pushed, so the review view stays honest.

**What can go wrong**
- **Replies are public and posted under your name.** Read the drafts.
- It can disagree with a reviewer. That is intended, but the reasoning is only as good as its reading of the code.
- It covers line-level review threads only, not top-level PR conversation comments.
- If a reply fails halfway, rerun `pr-comments` before retrying so nothing is posted twice.

**Repeat task it replaces:** opening each comment, fixing it, pushing, switching back to the browser, writing "done in abc123", clicking resolve, and doing that again for every thread.

---

## release-notes

### release-notes

**Use it when** you are cutting a release or updating the changelog.

**How**
```bash
release-notes                         # newest tag → HEAD
release-notes v1.2.0 v1.3.0           # explicit range
release-notes --to v1.3.0             # one release; FROM = the tag before it
release-notes --tag-pattern 'v*'      # only consider this tag family
```
Or ask "write release notes since v1.2.0". Claude rewrites the raw list into readable notes, shows you the draft, and only on your yes prepends it to `CHANGELOG.md` or runs `gh release create --draft`.

**What you get**
- Commits grouped as Breaking, Features, Bug fixes, Performance, Refactoring, Documentation, Maintenance and Other, with breaking changes first and their migration note shown.
- Each merged PR appears once, with a PR link and author when `gh` is logged in.
- It works fully offline with only git.
- Releases are always created as drafts, so a person publishes them.

**What can go wrong**
- It is only as good as your commit messages. Without Conventional Commits, everything lands in "Other" and Claude has to group it by reading the subjects.
- With several tag families (e.g. `app--v*` and `lib--v*`), the default FROM is the nearest tag of any family. Pass `--tag-pattern`.
- A single argument is FROM, not TO. Use `--to v1.3.0` for one existing release.
- With `gh`, it makes one API call per PR, which is slow on very large ranges.

**Repeat task it replaces:** scrolling `git log` between two tags, sorting commits into sections, looking up PR numbers, and writing the changelog entry by hand.
