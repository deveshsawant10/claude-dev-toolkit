#!/usr/bin/env bash
# ssm-run: run a shell command on an EC2 instance over SSM and print its output.
set -euo pipefail
# shellcheck disable=SC2034 # read by lib/common.sh
TOOL="ssm-run"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'USAGE'
usage: ssm-run <instance-id> [options] -- <command...>
       ssm-run <instance-id> [options] --file script.sh

  --profile P     AWS profile
  --region R      AWS region
  --timeout S     seconds to wait for the command (default 600)
  --file F        run a local script file instead of an inline command
  --no-redact     show secrets in the output instead of masking them

Runs as root through AWS-RunShellScript. Exits with the remote exit code.
USAGE
}

id="" PROFILE="" region="" timeout=600 file="" do_redact=1 cmd=()
while [ $# -gt 0 ]; do
  case $1 in
    --profile) [ $# -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
    --region) [ $# -ge 2 ] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    --timeout) [ $# -ge 2 ] || { usage >&2; exit 2; }; timeout=$2; shift 2 ;;
    --file) [ $# -ge 2 ] || { usage >&2; exit 2; }; file=$2; shift 2 ;;
    --no-redact) do_redact=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; cmd=("$@"); break ;;
    -*) usage >&2; exit 2 ;;
    *) [ -z "$id" ] || { usage >&2; exit 2; }; id=$1; shift ;;
  esac
done

valid_instance_id "$id" || { usage >&2; die 2 "missing or invalid instance id: '${id}'"; }
if ! [[ $timeout =~ ^[0-9]+$ ]] || [ "$timeout" -eq 0 ]; then die 2 "--timeout must be a positive number of seconds"; fi
if [ -n "$file" ]; then
  [ "${#cmd[@]}" -eq 0 ] || die 2 "use either --file or -- <command>, not both"
  [ -r "$file" ] || die 2 "cannot read $file"
  script=$(cat "$file")
else
  [ "${#cmd[@]}" -gt 0 ] || { usage >&2; die 2 "no command given"; }
  script="${cmd[*]}"
fi

set_aws_opts "$PROFILE" "$region"
require_aws
require_online "$id"
remote_exec "$id" "$script" "$timeout" "$do_redact"
exit "$REMOTE_RC"
