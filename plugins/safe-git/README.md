# safe-git

A `PreToolUse` hook that checks every `git push` Claude is about to run, so a session can't overwrite a teammate's work or land straight on `main` without you noticing.

| Situation | Result |
|---|---|
| Force push: `--force`, `-f` (also in `-uf`), a `+refspec`, `--mirror` | **Blocked.** Claude is told to `git pull --rebase` instead. |
| Your branch is behind or has diverged from the remote branch (checked with a fresh `git fetch`) | **Blocked.** The reason gives the exact `git pull --rebase <remote> <branch>` to run. |
| Push or `--delete` aimed at a protected branch (`main`, `master` by default) | **You are asked** to approve or reject. |
| Anything else | Silent. The push runs as normal. |

`--force-with-lease` and `--force-if-includes` are allowed: they refuse to overwrite commits you haven't seen, which is the safe way to rewrite a branch.

It only affects commands Claude runs through its Bash tool. Your own terminal is untouched.

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install safe-git@claude-dev-toolkit
```

Requires `git` and Python 3 (preinstalled on Linux and macOS). Nothing else is needed.

## What it understands

- Chained commands: `git add . && git commit -m x && git push`
- `git -C <dir> push …` and `cd <dir> && git push`
- Explicit refspecs: `git push origin HEAD:main`, `feat:refs/heads/main`
- Where the push goes: `branch.<b>.pushRemote`, `remote.pushDefault`, the branch's upstream, or `origin`
- `git push --all` checks every local branch

Text that only mentions a push, such as `echo "git push --force"`, is ignored.

## Configuration

To change the protected branches for one repository, add `.claude/safe-git.json` at its root:

```json
{ "protectedBranches": ["main", "release", "prod"] }
```

The list replaces the defaults. If the file is missing or invalid, the defaults `main` and `master` apply.

`SAFE_GIT_FETCH_TIMEOUT` sets the fetch timeout in seconds (default `8`).

## Fails open

If the hook cannot decide, the push goes ahead without a message. That covers: not a git repo, remote unreachable or offline, the branch not existing on the remote yet, a fetch timeout, a command it cannot parse, or any internal error. It only blocks when it is sure. It always exits 0, so it can never break an unrelated Bash call.

## Limits

- It only sees the command line. A push hidden inside a script (`./deploy.sh`) or an alias is not checked.
- The behind check is one extra `git fetch` per push, usually under a second.
- A protected-branch push still goes to the remote's own rules. This hook only adds a confirmation and does not replace branch protection on GitHub.

## Tests

```bash
tests/run    # real temporary git repos with a local bare "remote"; no network
```
