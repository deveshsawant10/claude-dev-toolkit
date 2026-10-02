#!/usr/bin/env bash
# Shared helpers for aws-ssm-tools. Sourced, never executed.
#
# Exit codes used by every tool:
#   2  bad usage
#   3  environment problem (aws missing, not logged in, plugin missing)
#   4  instance not reachable over SSM, or the remote command timed out

die() { local code=$1; shift; printf '%s: %s\n' "$TOOL" "$*" >&2; exit "$code"; }

# AWS CLI invocation with the caller's --profile / --region baked in.
AWS=(aws)
set_aws_opts() { # profile region
  AWS=(aws)
  [ -n "$1" ] && AWS+=(--profile "$1")
  [ -n "$2" ] && AWS+=(--region "$2")
  return 0
}

require_aws() {
  command -v perl >/dev/null 2>&1 || die 3 "perl not found (used to mask secrets in output)"
  command -v aws >/dev/null 2>&1 \
    || die 3 "aws CLI not found; install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  "${AWS[@]}" sts get-caller-identity >/dev/null 2>&1 \
    || die 3 "AWS credentials are missing or expired; run: aws sso login${PROFILE:+ --profile $PROFILE}"
}

valid_instance_id() { [[ $1 =~ ^i-[0-9a-f]{8,17}$ ]]; }

require_online() { # instance-id
  local ping
  ping=$("${AWS[@]}" ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$1" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null) || ping=""
  [ "$ping" = "Online" ] \
    || die 4 "$1 is not Online in SSM (got: ${ping:-nothing}). Check it is running, the SSM agent is up, and its IAM role allows SSM."
}

# Mask credentials before anything reaches the terminal (and the model's
# context). Covers GitHub tokens, AWS access key IDs, and key=value secrets.
redact() {
  perl -pe '
    s/\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/$1_***REDACTED***/g;
    s/\bgithub_pat_[A-Za-z0-9_]{20,}/github_pat_***REDACTED***/g;
    s/\b(AKIA|ASIA)[0-9A-Z]{16}\b/$1***REDACTED***/g;
    s/((?:aws_secret_access_key|secret|password|passwd|token)["\x27]?\s*[:=]\s*["\x27]?)(?!\S*REDACTED)[^"\x27\s]+/$1***REDACTED***/gi;
  '
}

# Run a bash script on an instance through AWS-RunShellScript and print its
# output. The script travels base64-encoded so no quoting can break it.
# Sets REMOTE_RC to the remote exit code.
remote_exec() { # instance-id script timeout-seconds redact(0|1)
  local id=$1 script=$2 timeout=$3 do_redact=$4 b64 cmd_id status deadline
  b64=$(printf '%s' "$script" | base64 | tr -d '\n')
  cmd_id=$("${AWS[@]}" ssm send-command \
    --instance-ids "$id" \
    --document-name AWS-RunShellScript \
    --comment "aws-ssm-tools $TOOL" \
    --timeout-seconds "$timeout" \
    --parameters "{\"commands\":[\"echo $b64 | base64 -d | bash\"],\"executionTimeout\":[\"$timeout\"]}" \
    --query Command.CommandId --output text) || die 4 "send-command failed for $id"

  deadline=$((SECONDS + timeout))
  while :; do
    status=$("${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
      --query Status --output text 2>/dev/null) || status=Pending
    case $status in
      Pending|InProgress|Delayed) ;;
      *) break ;;
    esac
    [ "$SECONDS" -ge "$deadline" ] && die 4 "timed out after ${timeout}s waiting for $cmd_id on $id"
    sleep "${SSM_POLL_SECONDS:-2}"
  done

  local out err filter=cat
  [ "$do_redact" = 1 ] && filter=redact
  out=$("${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
    --query StandardOutputContent --output text 2>/dev/null || true)
  err=$("${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
    --query StandardErrorContent --output text 2>/dev/null || true)
  REMOTE_RC=$("${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
    --query ResponseCode --output text 2>/dev/null || echo 1)
  [[ $REMOTE_RC =~ ^-?[0-9]+$ ]] || REMOTE_RC=1
  [ "$REMOTE_RC" -lt 0 ] && REMOTE_RC=1

  [ -n "$out" ] && printf '%s\n' "$out" | $filter
  [ -n "$err" ] && printf '%s\n' "$err" | $filter >&2
  if [ "$status" != Success ]; then
    printf '%s: command ended with status %s\n' "$TOOL" "$status" >&2
    [ "$REMOTE_RC" -eq 0 ] && REMOTE_RC=1
  fi
  if [ "${#out}" -ge 24000 ]; then
    printf '%s: output hit the SSM 24,000-character limit and was cut; narrow it (e.g. ssm-logs --lines/--grep)\n' "$TOOL" >&2
  fi
  return 0
}
