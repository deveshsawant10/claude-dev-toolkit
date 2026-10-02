# aws-ssm-tools

Work on private EC2 instances through AWS Systems Manager, with no bastion host, no open port 22 and no VPN. It works with a role that only has SSM access.

| Command | What it does |
|---|---|
| `ssm-ls` | List instances with their SSM reachability, newest first |
| `ssm-run` | Run a command on an instance and get its output and exit code |
| `ssm-logs` | Read or grep the newest log file matching a path or glob |
| `ssm-port` | Forward a local port to the instance, or to a host it can reach (e.g. a database) |
| `ssm-ssh` | Set up `ssh <instance-id>` / `scp` access, optionally expiring with `--ttl`; list it, remove it |

All of them mask secrets in output (GitHub tokens, AWS key ids, `password=`/`token=`/`secret=` values) unless you pass `--no-redact`.

Supports Linux and macOS.

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install aws-ssm-tools@claude-dev-toolkit
```

Installing puts the five commands on `PATH` inside Claude Code and adds the `ssm` skill, so asking "check the logs on i-0abc…" is enough.

## Requirements

- AWS CLI v2, logged in (`aws sso login --profile <P>` or any other credential source).
- `perl` (preinstalled on Linux and macOS).
- `ssm-port` and `ssm-ssh` only: [session-manager-plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) and `ssh-keygen`.
- Target instance: SSM agent running, with an instance role that includes `AmazonSSMManagedInstanceCore`.
- Your identity needs: `ssm:SendCommand`, `ssm:GetCommandInvocation`, `ssm:DescribeInstanceInformation`, `ec2:DescribeInstances`, plus `ssm:StartSession` for `ssm-port` and `ssm-ssh`.

## Usage

```bash
# Find instances. Only "online" ones are reachable.
ssm-ls --name worker --region ap-south-1
# i-0abc…  running  online  10.0.1.5  2026-10-02T03:05:31+00:00  my-worker

# Run a command (as root). Exit code is the remote one.
ssm-run i-0abc… -- 'df -h /; systemctl is-active nginx'
ssm-run i-0abc… --file ./diagnose.sh --timeout 900

# Read logs. Quote globs so your own shell doesn't expand them.
ssm-logs i-0abc… '/var/log/app/*.log' --grep 'ERROR|FATAL'
ssm-logs i-0abc… '/var/lib/amazon/toe/TOE_*/console.log' --lines 400
ssm-logs i-0abc… '/var/log/app/*.log' --list

# Port forwarding: no SSH key needed
ssm-port i-0abc… 8080                          # foreground, Ctrl-C to stop: http://localhost:8080
ssm-port i-0abc… 5432 --host mydb.xxxx.rds.amazonaws.com --local-port 15432 --background
ssm-port --list
ssm-port --stop 15432                          # or: ssm-port --stop all

# SSH / SCP
ssm-ssh i-0abc… --user ec2-user --profile prod --region ap-south-1
ssm-ssh i-0abc… --user ec2-user --ttl 2h       # key removes itself from the instance after 2h
ssh i-0abc…
scp ./build.tar.gz i-0abc…:/tmp/
ssm-ssh --list
ssm-ssh --remove i-0abc…            # remote key + local key + ~/.ssh/config block
ssm-ssh --remove i-0abc… --local-only   # instance already terminated
```

Every command accepts `--profile` and `--region`. `ssm-ssh --remove` reuses the ones you set up with.

## How `ssm-ssh` works

1. Creates an ed25519 key for this instance under `~/.ssh/aws-ssm-tools/<id>/`.
2. Pushes the public key into the remote user's `authorized_keys` with SSM `send-command`, tagged `aws-ssm-tools:<id>`. Other keys are left alone.
3. Puts a marked `Host <id>` block at the top of `~/.ssh/config`, with a `ProxyCommand` that tunnels through `aws ssm start-session --document-name AWS-StartSSHSession`.

`--remove` deletes only the tagged key line, the key directory and the marked block. Running setup twice replaces the key and block instead of adding duplicates.

With `--ttl 30m|2h|1d` (max 30d), setup also schedules removal of that key line **on the instance**: a transient `systemd-run` timer named `aws-ssm-tools-ttl-<id>`, or a detached `sleep` job where systemd is not available. Running setup again, or `--remove`, cancels the previous timer first. `ssm-ssh --list` shows `expires=` and marks keys past their expiry `EXPIRED`. The local key and config block are only cleaned up by `--remove`.

## How `ssm-port` works

It starts `aws ssm start-session` with `AWS-StartPortForwardingSession`, or `AWS-StartPortForwardingSessionToRemoteHost` with `--host`. The local port defaults to the remote one, or 10000+port for ports below 1024 (22 → 10022).

With `--background` the session runs detached in its own process group, and its pid, log and details are kept under `${XDG_STATE_HOME:-~/.local/state}/aws-ssm-tools/ports/`. The command returns once the local port accepts connections, or after 20s with the session log if it never does. `--stop` ends the whole process group, so no `session-manager-plugin` is left behind.

## Exit codes

`0` ok · `2` bad usage · `3` environment (missing tool, expired credentials) · `4` instance not Online in SSM, or timed out · any other value is the remote command's exit code.

## Limits

- SSM returns at most 24,000 characters of output per command. The tools warn when that limit is hit; narrow the query with `--grep`, `--lines` or `| head`.
- The remote side needs `bash`, `base64`, `getent` and GNU `sed`, which standard Amazon Linux and Ubuntu AMIs include.
- `--ttl` without systemd relies on a detached background job, which does not survive a reboot of the instance. In that case `--remove` is the reliable cleanup.
- Redaction is pattern-based. It catches common token formats, not every possible secret.

## Tests

```bash
tests/run    # fake aws CLI, throwaway HOME, plus shellcheck. No network.
```
