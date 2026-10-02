#!/usr/bin/env bash
# ssm-port: forward a local port to a port on (or reachable from) an EC2
# instance over SSM. No SSH key, no open inbound port.
set -euo pipefail
# shellcheck disable=SC2034 # read by lib/common.sh
TOOL="ssm-port"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'USAGE'
usage: ssm-port <instance-id> <remote-port> [--local-port L] [--host H]
                [--background] [--profile P] [--region R]
       ssm-port --list
       ssm-port --stop <local-port>|all

  --local-port L  local port to listen on (default: same as remote port, or
                  10000+port for ports below 1024, e.g. 22 -> 10022)
  --host H        forward to H:remote-port as seen from the instance
                  (e.g. an RDS endpoint) instead of the instance itself
  --background    detach, wait until the port is listening, then return
  --list          show background forwards started from this machine
  --stop L|all    stop a background forward

Foreground (default) runs until Ctrl-C.
USAGE
}

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/aws-ssm-tools/ports"

valid_port() { [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
listening() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
pmeta() { sed -n "s/^$2=//p" "$STATE/$1.meta" 2>/dev/null | head -n 1; }

stop_one() { # local-port
  local pid
  pid=$(cat "$STATE/$1.pid" 2>/dev/null || true)
  if alive "$pid"; then
    # The forward runs in its own process group (aws + session-manager-plugin).
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do alive "$pid" || break; sleep 0.2; done
    if alive "$pid"; then kill -9 -- "-$pid" 2>/dev/null || true; fi
  fi
  rm -f "$STATE/$1.pid" "$STATE/$1.meta" "$STATE/$1.log"
  printf 'stopped localhost:%s\n' "$1"
}

id="" rport="" lport="" host="" background=0 mode=start stop_arg="" PROFILE="" region=""
while [ $# -gt 0 ]; do
  case $1 in
    --local-port) [ $# -ge 2 ] || { usage >&2; exit 2; }; lport=$2; shift 2 ;;
    --host) [ $# -ge 2 ] || { usage >&2; exit 2; }; host=$2; shift 2 ;;
    --background) background=1; shift ;;
    --list) mode=list; shift ;;
    --stop) [ $# -ge 2 ] || { usage >&2; exit 2; }; mode=stop; stop_arg=$2; shift 2 ;;
    --profile) [ $# -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
    --region) [ $# -ge 2 ] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *)
      if [ -z "$id" ]; then id=$1
      elif [ -z "$rport" ]; then rport=$1
      else usage >&2; exit 2
      fi
      shift ;;
  esac
done

if [ "$mode" = list ]; then
  found=0
  for m in "$STATE"/*.meta; do
    [ -f "$m" ] || continue
    found=1
    l=$(basename "$m" .meta)
    pid=$(cat "$STATE/$l.pid" 2>/dev/null || true)
    status=dead
    alive "$pid" && status=running
    target="$(pmeta "$l" instance):$(pmeta "$l" remote_port)"
    [ -n "$(pmeta "$l" host)" ] && target="$(pmeta "$l" instance) -> $(pmeta "$l" host):$(pmeta "$l" remote_port)"
    printf 'localhost:%s\t%s\t%s\tpid=%s\tsince=%s\n' "$l" "$target" "$status" "${pid:-?}" "$(pmeta "$l" started)"
  done
  [ "$found" = 1 ] || printf 'no background forwards\n'
  exit 0
fi

if [ "$mode" = stop ]; then
  if [ "$stop_arg" = all ]; then
    any=0
    for m in "$STATE"/*.meta; do
      [ -f "$m" ] || continue
      any=1
      stop_one "$(basename "$m" .meta)"
    done
    [ "$any" = 1 ] || printf 'no background forwards\n'
    exit 0
  fi
  valid_port "$stop_arg" || die 2 "--stop takes a local port number or 'all'"
  [ -f "$STATE/$stop_arg.meta" ] || die 2 "no background forward on localhost:$stop_arg (see ssm-port --list)"
  stop_one "$stop_arg"
  exit 0
fi

valid_instance_id "$id" || { usage >&2; die 2 "missing or invalid instance id: '${id}'"; }
valid_port "$rport" || { usage >&2; die 2 "missing or invalid remote port: '${rport}'"; }
if [ -z "$lport" ]; then
  if [ "$rport" -lt 1024 ]; then lport=$((10000 + rport)); else lport=$rport; fi
fi
valid_port "$lport" || die 2 "invalid --local-port: $lport"
if [ -n "$host" ] && ! [[ $host =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
  die 2 "invalid --host: $host"
fi
listening "$lport" && die 2 "localhost:$lport is already in use; pick another with --local-port"
command -v session-manager-plugin >/dev/null 2>&1 \
  || die 3 "session-manager-plugin not found; install it: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"

set_aws_opts "$PROFILE" "$region"
require_aws
require_online "$id"

if [ -n "$host" ]; then
  doc="AWS-StartPortForwardingSessionToRemoteHost"
  params="{\"host\":[\"$host\"],\"portNumber\":[\"$rport\"],\"localPortNumber\":[\"$lport\"]}"
  target="$id -> $host:$rport"
else
  doc="AWS-StartPortForwardingSession"
  params="{\"portNumber\":[\"$rport\"],\"localPortNumber\":[\"$lport\"]}"
  target="$id:$rport"
fi
cmd=("${AWS[@]}" ssm start-session --target "$id" --document-name "$doc" --parameters "$params")

if [ "$background" = 0 ]; then
  printf 'forwarding localhost:%s -> %s (Ctrl-C to stop)\n' "$lport" "$target" >&2
  exec "${cmd[@]}"
fi

mkdir -p "$STATE"
chmod 700 "$STATE"
log="$STATE/$lport.log"
# New session (and process group) via perl, which exists on Linux and macOS,
# so --stop can take down aws and its session-manager-plugin child together.
nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!\n"' "${cmd[@]}" >"$log" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" >"$STATE/$lport.pid"
printf 'instance=%s\nremote_port=%s\nhost=%s\nprofile=%s\nregion=%s\nstarted=%s\n' \
  "$id" "$rport" "$host" "$PROFILE" "$region" "$(date -u +%Y-%m-%dT%H:%MZ)" >"$STATE/$lport.meta"

wait_s=${SSM_PORT_WAIT_SECONDS:-20}
deadline=$((SECONDS + wait_s))
until listening "$lport"; do
  if ! alive "$pid"; then
    printf '%s: the session ended before the port opened. Log:\n' "$TOOL" >&2
    redact <"$log" | tail -n 20 >&2
    rm -f "$STATE/$lport.pid" "$STATE/$lport.meta" "$log"
    exit 4
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    stop_one "$lport" >/dev/null
    die 4 "localhost:$lport did not start listening within ${wait_s}s"
  fi
  sleep 0.3
done

printf 'listening: localhost:%s -> %s (pid %s)\nstop with: ssm-port --stop %s\n' "$lport" "$target" "$pid" "$lport"
