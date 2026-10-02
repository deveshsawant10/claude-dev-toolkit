---
name: ssm
description: "Use to reach a private AWS EC2 instance through SSM (no bastion, no port 22): find an instance by name, run a command on it, read or grep a log file on it, or set up and later remove `ssh <instance-id>` / `scp` access. Triggers on an EC2 instance id (i-...), \"run this on the instance\", \"check the logs on the build box\", \"why did the Image Builder build fail\", \"ssh into\", \"copy this file to the server\"."
---

# ssm

Four commands on PATH, all non-interactive, so they are safe to call from the shell tool:

| Command | Use it to |
|---|---|
| `ssm-ls [--name TEXT] [--all]` | Find instances: id, state, whether SSM can reach it, IP, launch time, Name tag |
| `ssm-run <id> -- <command>` | Run a command as root and get its output; exits with the remote exit code |
| `ssm-logs <id> '<path-or-glob>' [--lines N] [--grep RE] [--list]` | Read the end of a log, newest matching file first |
| `ssm-ssh <id> --user U` / `ssm-ssh --remove <id>` / `ssm-ssh --list` | Make `ssh <id>` and `scp` work; undo it |

Every command takes `--profile P` and `--region R`. If the user has said which account or region they mean, pass both every time.

## Choosing the command

- **The user names an instance by role, not id** ("the build instance", "the core worker"): run `ssm-ls --name <word>` first and confirm which id is meant if more than one matches. Only `online` rows are reachable.
- **One-off question about the box** (disk, process, config value, service status): use `ssm-run`. Do not set up SSH for this.
- **Anything in a log file**: use `ssm-logs`, not `ssm-run cat`. It picks the newest file for a glob and keeps output small. Start with `--grep 'error|fail|fatal'` (case matters, so add capitalised forms if needed), then widen with `--lines`.
- **Interactive work, port forwarding, or copying files**: use `ssm-ssh`. When the task is finished, offer `ssm-ssh --remove <id>`. A pushed key is real access and must not be left behind.

## Rules

1. **Output is masked on purpose.** GitHub tokens, AWS key ids and `password=`/`token=`/`secret=` values are replaced with `***REDACTED***`. Never pass `--no-redact` unless the user explicitly asks to see a secret, and never repeat a secret back.
2. **`ssm-run` runs as root.** Before running anything that changes state (restarts, deletes, package installs, edits), state the exact command and get the user's go-ahead. Read-only commands need no confirmation.
3. **`ssm-ssh` needs `--user`.** Use `ec2-user` on Amazon Linux and `ubuntu` on Ubuntu. If unsure, check first: `ssm-run <id> -- 'grep -E "^(ID|NAME)=" /etc/os-release'`.
4. **Output is capped at 24,000 characters by SSM.** If a command warns that its output was cut, narrow it (`--grep`, `--lines`, `| head`) instead of retrying the same thing.

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | success | |
| 2 | bad usage | fix the arguments |
| 3 | environment: aws/perl/session-manager-plugin missing, or credentials expired | relay the message. For expired SSO, tell the user to run `aws sso login --profile <P>` themselves |
| 4 | instance not Online in SSM, or timed out | check `ssm-ls`; the instance may be stopped or its agent down |
| other | the remote command's own exit code (`ssm-run`, `ssm-logs`) | read stderr |

## Debugging an EC2 Image Builder build

The build instance keeps running only while the build is in progress or after it has failed, so find it quickly:

```bash
ssm-ls --name "Build instance"                  # newest first
ssm-logs <id> '/var/lib/amazon/toe/TOE_*/console.log' --grep 'ERROR|Error|FAILED|exit status'
ssm-logs <id> '/var/lib/amazon/toe/TOE_*/console.log' --lines 400
```

Component steps print their output only when each step finishes, so a step that is still running shows nothing yet.
