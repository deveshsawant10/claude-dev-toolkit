#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=helpers.sh
. "$(dirname "$0")/helpers.sh"

export XDG_STATE_HOME="$SANDBOX/state"
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
cleanup() { "$BIN/ssm-port" --stop all >/dev/null 2>&1; rm -rf "$SANDBOX"; }
trap cleanup EXIT

L=$(free_port)
out=$("$BIN/ssm-port" "$ID" 5432 --local-port "$L" --background 2>&1); rc=$?
assert_eq "background start exits 0" "$rc" 0
assert_contains "reports the forward" "$out" "listening: localhost:$L -> $ID:5432"
assert_eq "local port really listens" "$(python3 -c "import socket;s=socket.create_connection(('127.0.0.1',$L),2);print(s.recv(64).decode().strip())")" "stub-tunnel"
assert_contains "uses the port-forwarding document" "$(calls | grep start-session)" "--document-name AWS-StartPortForwardingSession --parameters"
assert_contains "passes both ports" "$(calls | grep start-session)" '"portNumber":["5432"],"localPortNumber":["'"$L"'"]'
out=$("$BIN/ssm-port" --list)
assert_contains "--list shows it running" "$out" "localhost:$L"$'\t'"$ID:5432"$'\t'"running"

out=$("$BIN/ssm-port" "$ID" 5432 --local-port "$L" --background 2>&1); rc=$?
assert_eq "busy local port exits 2" "$rc" 2
assert_contains "busy port message" "$out" "already in use"

pid=$(cat "$XDG_STATE_HOME/aws-ssm-tools/ports/$L.pid")
out=$("$BIN/ssm-port" --stop "$L" 2>&1); rc=$?
assert_eq "stop exits 0" "$rc" 0
assert_eq "tunnel process is gone" "$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)" no
assert_eq "port is free again" "$( (exec 3<>"/dev/tcp/127.0.0.1/$L") 2>/dev/null && echo busy || echo free)" free
assert_contains "--list empty after stop" "$("$BIN/ssm-port" --list)" "no background forwards"

L2=$(free_port)
"$BIN/ssm-port" "$ID" 3306 --host db.internal.example --local-port "$L2" --background >/dev/null 2>&1
c=$(calls | grep start-session | tail -1)
assert_contains "--host uses the remote-host document" "$c" "AWS-StartPortForwardingSessionToRemoteHost"
assert_contains "--host passes the host" "$c" '"host":["db.internal.example"]'
assert_contains "--list shows the remote host" "$("$BIN/ssm-port" --list)" "$ID -> db.internal.example:3306"
L3=$(free_port)
"$BIN/ssm-port" "$ID" 8080 --local-port "$L3" --background >/dev/null 2>&1
"$BIN/ssm-port" --stop all >/dev/null 2>&1
assert_contains "--stop all stops everything" "$("$BIN/ssm-port" --list)" "no background forwards"

out=$(AWS_STUB_PORT=oneshot "$BIN/ssm-port" "$ID" 22 --profile prod 2>&1); rc=$?
assert_eq "foreground passes through the session exit" "$rc" 0
assert_contains "port 22 defaults to local 10022" "$(calls | grep start-session | tail -1)" '"localPortNumber":["10022"]'
assert_contains "foreground passes the profile" "$(calls | grep start-session | tail -1)" "--profile prod"

L4=$(free_port)
out=$(AWS_STUB_PORT=fail "$BIN/ssm-port" "$ID" 5432 --local-port "$L4" --background 2>&1); rc=$?
assert_eq "tunnel that dies exits 4" "$rc" 4
assert_contains "shows the session log" "$out" "TargetNotConnected"
assert_contains "no leftover state" "$("$BIN/ssm-port" --list)" "no background forwards"

L5=$(free_port)
out=$(AWS_STUB_PORT=silent SSM_PORT_WAIT_SECONDS=2 "$BIN/ssm-port" "$ID" 5432 --local-port "$L5" --background 2>&1); rc=$?
assert_eq "port that never opens exits 4" "$rc" 4
assert_contains "wait timeout message" "$out" "did not start listening"
assert_contains "timed-out tunnel is cleaned up" "$("$BIN/ssm-port" --list)" "no background forwards"

out=$(AWS_STUB_PING=ConnectionLost "$BIN/ssm-port" "$ID" 5432 --local-port "$(free_port)" --background 2>&1); rc=$?
assert_eq "offline instance exits 4" "$rc" 4

for args in "$ID" "$ID 0" "$ID 70000" "not-an-id 22" "$ID 22 --local-port x" "$ID 22 --host bad;host"; do
  # shellcheck disable=SC2086 # word splitting is the point here.
  out=$("$BIN/ssm-port" $args 2>&1); rc=$?
  assert_eq "rejects: $args" "$rc" 2
done
out=$("$BIN/ssm-port" --stop 12 2>&1); rc=$?
assert_eq "stop of unknown port exits 2" "$rc" 2

finish
