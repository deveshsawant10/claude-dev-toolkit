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
| aws-ssm-tools | [`ssm-ssh`](#ssm-ssh) | Temporary `ssh` / `scp` access |

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

### ssm-ssh

**Use it when** you need a real session: interactive debugging, `scp` files in or out, or port forwarding with `ssh -L`.

**How**
```bash
ssm-ssh i-0abc… --user ec2-user --profile prod --region ap-south-1
ssh i-0abc…
scp ./patch.tar.gz i-0abc…:/tmp/
ssm-ssh --list
ssm-ssh --remove i-0abc…                 # when done
ssm-ssh --remove i-0abc… --local-only    # instance already gone
```

**What you get**
- Plain `ssh <instance-id>` and `scp` that work through SSM, with no key pairs to manage and no security group changes.
- A separate key per instance, tagged so that `--remove` deletes only that key and leaves other people's keys alone.
- Running it again is safe: it replaces the key and config instead of duplicating them.

**What can go wrong**
- **A pushed key is real access until you remove it.** Run `--remove` when you're done, and use `ssm-ssh --list` to see what's still active.
- `--user` must exist on the instance (`ec2-user` on Amazon Linux, `ubuntu` on Ubuntu). If the user is wrong, the command fails and changes nothing.
- It needs `session-manager-plugin` installed locally.
- It edits `~/.ssh/config`, only inside its own marked block, placed at the top so it takes precedence over `Host *` rules.
- If the instance is replaced (for example by an autoscaling group), the new instance has a new id, so run setup again.

**Repeat task it replaces:** asking for a bastion or a port 22 rule, hunting for the right `.pem`, or typing long `aws ssm start-session` commands by hand.
