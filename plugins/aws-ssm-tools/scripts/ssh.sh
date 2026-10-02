#!/usr/bin/env bash
# ssm-ssh: make `ssh <instance-id>` and `scp` work over SSM, then undo it.
#
# Setup pushes a per-instance ed25519 public key into the remote user's
# authorized_keys (over SSM, so port 22 is never opened) and adds a Host
# block to ~/.ssh/config whose ProxyCommand tunnels through
# `aws ssm start-session`. --remove reverses both halves.
set -euo pipefail
# shellcheck disable=SC2034 # read by lib/common.sh
TOOL="ssm-ssh"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'USAGE'
usage: ssm-ssh <instance-id> --user U [--ttl DURATION] [--profile P] [--region R]
       ssm-ssh --remove <instance-id> [--local-only]
       ssm-ssh --list

  --user U       remote login user (ec2-user on Amazon Linux, ubuntu on Ubuntu)
  --ttl D        remove the key from the instance automatically after D
                 (e.g. 30m, 2h, 1d; plain number = seconds; max 30d)
  --remove       delete the key from the instance and the local key + ssh config
  --local-only   with --remove: skip the instance (it is gone or unreachable)
  --list         show instances currently set up from this machine

After setup:  ssh <instance-id>     scp file <instance-id>:/tmp/
USAGE
}

KEY_ROOT="$HOME/.ssh/aws-ssm-tools"
SSH_CONFIG="$HOME/.ssh/config"

begin_mark() { printf '# >>> aws-ssm-tools %s\n' "$1"; }
end_mark() { printf '# <<< aws-ssm-tools %s\n' "$1"; }

drop_config_block() { # instance-id
  [ -f "$SSH_CONFIG" ] || return 0
  local tmp
  tmp=$(mktemp)
  awk -v b="$(begin_mark "$1")" -v e="$(end_mark "$1")" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip' "$SSH_CONFIG" >"$tmp"
  cat "$tmp" >"$SSH_CONFIG"
  rm -f "$tmp"
}

meta() { # instance-id key -> value from the saved meta file
  sed -n "s/^$2=//p" "$KEY_ROOT/$1/meta" 2>/dev/null | head -n 1
}

ttl_seconds() { # 90 | 30s | 30m | 2h | 1d -> seconds, or nothing if invalid
  [[ $1 =~ ^([0-9]+)([smhd]?)$ ]] || return 1
  local n=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
  case $unit in
    ''|s) echo $((10#$n)) ;;
    m) echo $((10#$n * 60)) ;;
    h) echo $((10#$n * 3600)) ;;
    d) echo $((10#$n * 86400)) ;;
  esac
}

utc_from_epoch() { perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%MZ", gmtime($ARGV[0]))' "$1"; }

# Remote snippets. __MARKER__ / __UNIT__ are filled in below; $ak and $home
# are remote variables, set before these run.
# shellcheck disable=SC2016 # expanded on the instance, not here.
CANCEL_TTL='unit=__UNIT__
pidf="$home/.ssh/.__UNIT__.pid"
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
  systemctl reset-failed "$unit.timer" "$unit.service" >/dev/null 2>&1 || true
fi
if [ -f "$pidf" ]; then
  p=$(cat "$pidf")
  kill -- "-$p" 2>/dev/null || kill "$p" 2>/dev/null || true
  rm -f "$pidf"
fi'
# shellcheck disable=SC2016
SCHEDULE_TTL='rmc="sed -i '"'"'/ __MARKER__\$/d'"'"' $ak; rm -f $pidf"
if command -v systemd-run >/dev/null 2>&1 \
   && systemd-run --quiet --on-active=__SECS__ --unit "$unit" \
        --description "aws-ssm-tools: expire SSH key __MARKER__" \
        /bin/sh -c "$rmc" >/dev/null 2>&1; then
  echo ttl=systemd
else
  if command -v setsid >/dev/null 2>&1; then s=setsid; else s=; fi
  nohup $s sh -c "sleep __SECS__; $rmc" >/dev/null 2>&1 &
  echo $! >"$pidf"
  echo ttl=background
fi'

mode=setup id="" user="" PROFILE="" region="" local_only=0 ttl=""
while [ $# -gt 0 ]; do
  case $1 in
    --user) [ $# -ge 2 ] || { usage >&2; exit 2; }; user=$2; shift 2 ;;
    --ttl) [ $# -ge 2 ] || { usage >&2; exit 2; }; ttl=$2; shift 2 ;;
    --profile) [ $# -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
    --region) [ $# -ge 2 ] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    --remove) mode=remove; shift ;;
    --local-only) local_only=1; shift ;;
    --list) mode=list; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) [ -z "$id" ] || { usage >&2; exit 2; }; id=$1; shift ;;
  esac
done

if [ "$mode" = list ]; then
  found=0
  for d in "$KEY_ROOT"/i-*; do
    [ -f "$d/meta" ] || continue
    found=1
    i=$(basename "$d")
    exp=$(meta "$i" expires)
    exp_epoch=$(meta "$i" expires_epoch)
    if [ -z "$exp" ]; then exp=never
    elif [ -n "$exp_epoch" ] && [ "$(date -u +%s)" -ge "$exp_epoch" ]; then exp="$exp EXPIRED"
    fi
    printf '%s\tuser=%s\tprofile=%s\tregion=%s\tsince=%s\texpires=%s\n' "$i" "$(meta "$i" user)" \
      "$(meta "$i" profile)" "$(meta "$i" region)" "$(meta "$i" created)" "$exp"
  done
  [ "$found" = 1 ] || printf 'no instances set up\n'
  exit 0
fi

valid_instance_id "$id" || { usage >&2; die 2 "missing or invalid instance id: '${id}'"; }
marker="aws-ssm-tools:$id"
unit="aws-ssm-tools-ttl-$id"
cancel_ttl=${CANCEL_TTL//__UNIT__/$unit}

if [ "$mode" = remove ]; then
  [ -d "$KEY_ROOT/$id" ] || [ "$local_only" = 1 ] || die 2 "$id is not set up from this machine (see ssm-ssh --list)"
  if [ "$local_only" = 0 ]; then
    [ -n "$user" ] || user=$(meta "$id" user)
    [ -n "$PROFILE" ] || PROFILE=$(meta "$id" profile)
    [ -n "$region" ] || region=$(meta "$id" region)
    [ -n "$user" ] || die 2 "no saved user for $id; pass --user"
    set_aws_opts "$PROFILE" "$region"
    require_aws
    require_online "$id"
    remote_exec "$id" "set -e
home=\$(getent passwd $(printf '%q' "$user") | cut -d: -f6)
ak=\"\$home/.ssh/authorized_keys\"
$cancel_ttl
if [ -f \"\$ak\" ]; then sed -i '/ $marker\$/d' \"\$ak\"; fi
echo removed" 60 1 >/dev/null
    [ "$REMOTE_RC" -eq 0 ] || die 4 "could not remove the key on $id; rerun, or use --local-only if the instance is gone"
  fi
  drop_config_block "$id"
  rm -rf "${KEY_ROOT:?}/$id"
  printf 'removed %s: remote key%s, local key, ssh config block\n' "$id" \
    "$([ "$local_only" = 1 ] && printf ' (skipped)')"
  exit 0
fi

[ -n "$user" ] || { usage >&2; die 2 "--user is required (ec2-user on Amazon Linux, ubuntu on Ubuntu)"; }
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || die 2 "invalid user name: $user"
ttl_secs=""
if [ -n "$ttl" ]; then
  ttl_secs=$(ttl_seconds "$ttl") || die 2 "invalid --ttl '$ttl' (use e.g. 30m, 2h, 1d)"
  if [ "$ttl_secs" -lt 1 ] || [ "$ttl_secs" -gt 2592000 ]; then die 2 "--ttl must be between 1s and 30d"; fi
fi
command -v session-manager-plugin >/dev/null 2>&1 \
  || die 3 "session-manager-plugin not found; install it: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
command -v ssh-keygen >/dev/null 2>&1 || die 3 "ssh-keygen not found"

set_aws_opts "$PROFILE" "$region"
require_aws
require_online "$id"

dir="$KEY_ROOT/$id"
key="$dir/id_ed25519"
fresh=0
[ -d "$dir" ] || fresh=1
mkdir -p "$dir"
chmod 700 "$KEY_ROOT" "$dir"
[ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -C "$marker" -f "$key"
pub=$(cat "$key.pub")

schedule=""
if [ -n "$ttl_secs" ]; then
  schedule=${SCHEDULE_TTL//__MARKER__/$marker}
  schedule=${schedule//__SECS__/$ttl_secs}
fi

remote_exec "$id" "set -e
u=$(printf '%q' "$user")
getent passwd \"\$u\" >/dev/null || { echo \"no user \$u on this instance\" >&2; exit 3; }
home=\$(getent passwd \"\$u\" | cut -d: -f6)
mkdir -p \"\$home/.ssh\"
ak=\"\$home/.ssh/authorized_keys\"
touch \"\$ak\"
sed -i '/ $marker\$/d' \"\$ak\"
echo $(printf '%q' "$pub") >>\"\$ak\"
chown -R \"\$u\": \"\$home/.ssh\"
chmod 700 \"\$home/.ssh\"
chmod 600 \"\$ak\"
$cancel_ttl
$schedule
echo pushed" 60 1 >"$dir/push.out"
if [ "$REMOTE_RC" -ne 0 ] && [ "$fresh" = 1 ]; then rm -rf "${dir:?}"; fi
[ "$REMOTE_RC" -eq 0 ] || die 4 "pushing the key to $id failed (exit $REMOTE_RC); check that user '$user' exists there"

proxy="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
[ -n "$PROFILE" ] && proxy+=" --profile $PROFILE"
[ -n "$region" ] && proxy+=" --region $region"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
drop_config_block "$id"
# Prepend: ssh uses the first matching Host block, so ours must win over any
# broad `Host *` / `Host i-*` entries further down.
tmp=$(mktemp)
{
  begin_mark "$id"
  printf 'Host %s\n  User %s\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$id" "$user" "$key"
  printf '  StrictHostKeyChecking accept-new\n  ProxyCommand %s\n' "$proxy"
  end_mark "$id"
  cat "$SSH_CONFIG"
} >"$tmp"
cat "$tmp" >"$SSH_CONFIG"
rm -f "$tmp"

ttl_how=$(sed -n 's/^ttl=//p' "$dir/push.out" | head -n 1)
rm -f "$dir/push.out"
{
  printf 'user=%s\nprofile=%s\nregion=%s\ncreated=%s\n' "$user" "$PROFILE" "$region" \
    "$(date -u +%Y-%m-%dT%H:%MZ)"
  if [ -n "$ttl_secs" ]; then
    exp_epoch=$(( $(date -u +%s) + ttl_secs ))
    printf 'expires=%s\nexpires_epoch=%s\nttl_mode=%s\n' "$(utc_from_epoch "$exp_epoch")" "$exp_epoch" "$ttl_how"
  fi
} >"$dir/meta"

printf 'ready: ssh %s    scp <file> %s:<path>\n' "$id" "$id"
if [ -n "$ttl_secs" ]; then
  printf 'key expires on the instance at %s (via %s); ssm-ssh --remove %s also cleans up locally\n' \
    "$(meta "$id" expires)" "${ttl_how:-unknown}" "$id"
else
  printf 'when done: ssm-ssh --remove %s\n' "$id"
fi
