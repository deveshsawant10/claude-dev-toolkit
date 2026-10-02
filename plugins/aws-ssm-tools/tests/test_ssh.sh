#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

ak="$FAKE_REMOTE_HOME/.ssh/authorized_keys"
cfg="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh" "$FAKE_REMOTE_HOME/.ssh"
printf 'Host *\n  ServerAliveInterval 30\n' >"$cfg"
printf 'ssh-ed25519 AAAAexisting someone@laptop\n' >"$ak"

out=$("$BIN/ssm-ssh" "$ID" --user ec2-user --profile prod --region ap-south-1 2>&1); rc=$?
assert_eq "setup exits 0" "$rc" 0
assert_contains "prints how to connect" "$out" "ssh $ID"
assert_contains "key pushed to authorized_keys" "$(cat "$ak")" "aws-ssm-tools:$ID"
assert_contains "existing keys kept" "$(cat "$ak")" "someone@laptop"
assert_eq "local key created" "$([ -f "$HOME/.ssh/aws-ssm-tools/$ID/id_ed25519" ] && echo yes)" yes
assert_contains "config has Host block" "$(cat "$cfg")" "Host $ID"
assert_contains "config uses SSM proxy with profile" "$(cat "$cfg")" "AWS-StartSSHSession --parameters portNumber=%p --profile prod --region ap-south-1"
assert_contains "config user" "$(cat "$cfg")" "User ec2-user"
assert_eq "our block comes before Host *" "$(grep -m1 '^Host' "$cfg")" "Host $ID"
assert_contains "existing config kept" "$(cat "$cfg")" "ServerAliveInterval 30"

"$BIN/ssm-ssh" "$ID" --user ec2-user --profile prod --region ap-south-1 >/dev/null 2>&1
assert_eq "rerun does not duplicate the key" "$(grep -c "aws-ssm-tools:$ID" "$ak")" 1
assert_eq "rerun does not duplicate the config block" "$(grep -c "^Host $ID" "$cfg")" 1

out=$("$BIN/ssm-ssh" --list 2>&1)
assert_contains "--list shows the instance" "$out" "$ID"$'\t'"user=ec2-user"$'\t'"profile=prod"

out=$("$BIN/ssm-ssh" --remove "$ID" 2>&1); rc=$?
assert_eq "remove exits 0" "$rc" 0
assert_not_contains "remote key removed" "$(cat "$ak")" "aws-ssm-tools:$ID"
assert_contains "other remote keys untouched" "$(cat "$ak")" "someone@laptop"
assert_not_contains "config block removed" "$(cat "$cfg")" "$ID"
assert_contains "rest of config untouched" "$(cat "$cfg")" "ServerAliveInterval 30"
assert_eq "local key dir removed" "$([ -d "$HOME/.ssh/aws-ssm-tools/$ID" ] && echo yes || echo no)" no
assert_contains "remove reused the saved profile" "$(calls | grep send-command | tail -1)" "--profile prod"
assert_contains "--list empty after remove" "$("$BIN/ssm-ssh" --list)" "no instances set up"

"$BIN/ssm-ssh" "$ID" --user ec2-user >/dev/null 2>&1
out=$(AWS_STUB_PING=ConnectionLost "$BIN/ssm-ssh" --remove "$ID" --local-only 2>&1); rc=$?
assert_eq "--local-only works when instance is gone" "$rc" 0
assert_not_contains "--local-only cleans config" "$(cat "$cfg")" "$ID"

out=$("$BIN/ssm-ssh" "$ID" --user nobody-here 2>&1); rc=$?
assert_eq "unknown remote user exits 4" "$rc" 4
assert_contains "names the user" "$out" "nobody-here"
assert_eq "failed setup leaves no local key" "$([ -d "$HOME/.ssh/aws-ssm-tools/$ID" ] && echo yes || echo no)" no
assert_not_contains "failed setup leaves no config block" "$(cat "$cfg")" "Host $ID"

out=$("$BIN/ssm-ssh" "$ID" 2>&1); rc=$?
assert_eq "missing --user exits 2" "$rc" 2
out=$("$BIN/ssm-ssh" "$ID" --user 'root;id' 2>&1); rc=$?
assert_eq "hostile user name rejected" "$rc" 2
out=$("$BIN/ssm-ssh" --remove i-0ddddddddddddddd4 2>&1); rc=$?
assert_eq "remove of unknown instance exits 2" "$rc" 2

# --- --ttl -------------------------------------------------------------
rm -f "$AWS_STUB_STATE/systemd-run.calls" "$AWS_STUB_STATE/systemctl.calls"
out=$("$BIN/ssm-ssh" "$ID" --user ec2-user --ttl 2h 2>&1); rc=$?
assert_eq "ttl setup exits 0" "$rc" 0
assert_contains "ttl uses systemd-run when present" "$out" "via systemd"
sr=$(cat "$AWS_STUB_STATE/systemd-run.calls" 2>/dev/null)
assert_contains "timer is 2h in seconds" "$sr" "--on-active=7200"
assert_contains "timer unit is per instance" "$sr" "--unit aws-ssm-tools-ttl-$ID"
assert_contains "timer deletes only our tagged line" "$sr" "/ aws-ssm-tools:$ID\$/d"
assert_contains "old timer stopped before scheduling" "$(cat "$AWS_STUB_STATE/systemctl.calls")" "stop aws-ssm-tools-ttl-$ID.timer"
assert_contains "--list shows expiry" "$("$BIN/ssm-ssh" --list)" "expires=20"
assert_not_contains "--list not expired yet" "$("$BIN/ssm-ssh" --list)" "EXPIRED"
meta="$HOME/.ssh/aws-ssm-tools/$ID/meta"
sed -i.bak 's/^expires_epoch=.*/expires_epoch=1/' "$meta" && rm -f "$meta.bak"
assert_contains "--list marks past expiry" "$("$BIN/ssm-ssh" --list)" "EXPIRED"

"$BIN/ssm-ssh" "$ID" --user ec2-user >/dev/null 2>&1
assert_contains "--list shows never without ttl" "$("$BIN/ssm-ssh" --list)" "expires=never"

out=$(FAKE_SYSTEMD=fail "$BIN/ssm-ssh" "$ID" --user ec2-user --ttl 2s 2>&1); rc=$?
assert_eq "fallback ttl setup exits 0" "$rc" 0
assert_contains "falls back to a background timer" "$out" "via background"
assert_contains "key present right after setup" "$(cat "$ak")" "aws-ssm-tools:$ID"
sleep 4
assert_not_contains "fallback timer removed the key" "$(cat "$ak")" "aws-ssm-tools:$ID"
assert_contains "fallback timer kept other keys" "$(cat "$ak")" "someone@laptop"

out=$(FAKE_SYSTEMD=fail "$BIN/ssm-ssh" "$ID" --user ec2-user --ttl 1h 2>&1)
pidf="$FAKE_REMOTE_HOME/.ssh/.aws-ssm-tools-ttl-$ID.pid"
pid=$(cat "$pidf" 2>/dev/null)
assert_eq "fallback timer process is running" "$(kill -0 "$pid" 2>/dev/null && echo yes)" yes
"$BIN/ssm-ssh" --remove "$ID" >/dev/null 2>&1
sleep 0.5
assert_eq "remove cancels the fallback timer" "$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)" no
assert_eq "remove deletes the pid file" "$([ -f "$pidf" ] && echo yes || echo no)" no

for bad in 0 5x -1 31d; do
  out=$("$BIN/ssm-ssh" "$ID" --user ec2-user --ttl "$bad" 2>&1); rc=$?
  assert_eq "invalid --ttl $bad exits 2" "$rc" 2
done

finish
