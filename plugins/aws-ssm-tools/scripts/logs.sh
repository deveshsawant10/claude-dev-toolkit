#!/usr/bin/env bash
# ssm-logs: show the end of a log file on an EC2 instance over SSM.
set -euo pipefail
# shellcheck disable=SC2034 # read by lib/common.sh
TOOL="ssm-logs"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'USAGE'
usage: ssm-logs <instance-id> <path-or-glob> [options]

  --lines N       how many lines from the end (default 200)
  --grep RE       only lines matching this extended regex (searches the whole file)
  --list          list matching files (newest first) instead of reading one
  --profile P     AWS profile
  --region R      AWS region
  --no-redact     show secrets instead of masking them

A glob picks the newest matching file, e.g.
  ssm-logs i-0abc '/var/lib/amazon/toe/TOE_*/console.log' --grep 'error|fail'
Quote globs so your local shell does not expand them.
USAGE
}

id="" path="" PROFILE="" region="" lines=200 pattern="" list=0 do_redact=1
while [ $# -gt 0 ]; do
  case $1 in
    --lines) [ $# -ge 2 ] || { usage >&2; exit 2; }; lines=$2; shift 2 ;;
    --grep) [ $# -ge 2 ] || { usage >&2; exit 2; }; pattern=$2; shift 2 ;;
    --list) list=1; shift ;;
    --profile) [ $# -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
    --region) [ $# -ge 2 ] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    --no-redact) do_redact=0; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *)
      if [ -z "$id" ]; then id=$1
      elif [ -z "$path" ]; then path=$1
      else usage >&2; exit 2
      fi
      shift ;;
  esac
done

valid_instance_id "$id" || { usage >&2; die 2 "missing or invalid instance id: '${id}'"; }
[ -n "$path" ] || { usage >&2; die 2 "missing log path"; }
[[ $path == /* ]] || die 2 "log path must be absolute: $path"
[[ $path =~ ^[A-Za-z0-9_./*?@+:,-]+$ ]] || die 2 "log path has characters outside [A-Za-z0-9_./*?@+:,-]: $path"
if ! [[ $lines =~ ^[0-9]+$ ]] || [ "$lines" -eq 0 ]; then die 2 "--lines must be a positive number"; fi

# The path is a validated glob, so it is safe to leave unquoted on the remote
# side; the grep pattern is user text, so it is quoted with %q.
script="shopt -s nullglob
files=( $path )
[ \${#files[@]} -gt 0 ] || { echo 'no file matches $path' >&2; exit 1; }"
if [ "$list" = 1 ]; then
  script+="
ls -1t -- \"\${files[@]}\""
else
  script+="
f=\$(ls -1t -- \"\${files[@]}\" | head -n 1)
echo \"==> \$f\""
  if [ -n "$pattern" ]; then
    script+="
grep -E -- $(printf '%q' "$pattern") \"\$f\" | tail -n $lines || true"
  else
    script+="
tail -n $lines -- \"\$f\""
  fi
fi

set_aws_opts "$PROFILE" "$region"
require_aws
require_online "$id"
remote_exec "$id" "$script" 120 "$do_redact"
exit "$REMOTE_RC"
