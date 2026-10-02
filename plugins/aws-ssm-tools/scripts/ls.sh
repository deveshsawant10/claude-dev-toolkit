#!/usr/bin/env bash
# ssm-ls: list running EC2 instances and whether SSM can reach them.
set -euo pipefail
# shellcheck disable=SC2034 # read by lib/common.sh
TOOL="ssm-ls"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'USAGE'
usage: ssm-ls [--name TEXT] [--all] [--profile P] [--region R]

  --name TEXT   only instances whose Name tag contains TEXT (case-sensitive)
  --all         include stopped/pending instances, not just running ones
  --profile P   AWS profile
  --region R    AWS region

Columns: instance-id  state  ssm  private-ip  launched  name
USAGE
}

name="" all=0 PROFILE="" region=""
while [ $# -gt 0 ]; do
  case $1 in
    --name) [ $# -ge 2 ] || { usage >&2; exit 2; }; name=$2; shift 2 ;;
    --all) all=1; shift ;;
    --profile) [ $# -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
    --region) [ $# -ge 2 ] || { usage >&2; exit 2; }; region=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

set_aws_opts "$PROFILE" "$region"
require_aws

filters=()
[ "$all" = 1 ] || filters+=("Name=instance-state-name,Values=running")
[ -n "$name" ] && filters+=("Name=tag:Name,Values=*${name}*")
# JMESPath uses backticks for literals; they are not shell expansions.
# shellcheck disable=SC2016
args=(ec2 describe-instances --output text
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,LaunchTime,Tags[?Key==`Name`]|[0].Value]')
[ "${#filters[@]}" -gt 0 ] && args+=(--filters "${filters[@]}")
rows=$("${AWS[@]}" "${args[@]}") || die 3 "ec2 describe-instances failed (does your role allow it?)"

# shellcheck disable=SC2016
online=$("${AWS[@]}" ssm describe-instance-information --output text \
  --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' 2>/dev/null || true)

[ -n "$rows" ] || { printf 'no matching instances\n'; exit 0; }
printf '%s\n' "$rows" | sort -t$'\t' -k4,4r | while IFS=$'\t' read -r iid state ip launched label; do
  ssm=offline
  case " $(printf '%s' "$online" | tr '\t\n' '  ') " in *" $iid "*) ssm=online ;; esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$iid" "$state" "$ssm" "${ip:-None}" "${launched%%.*}" "${label:-None}"
done
