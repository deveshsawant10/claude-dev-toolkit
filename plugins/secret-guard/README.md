# secret-guard

Stops credentials from leaking through a Claude Code session, at two points:

| Hook | What it blocks |
|---|---|
| `UserPromptSubmit` | A **message you send** that contains a secret. The message is not sent and is not added to the conversation. You are told to revoke or rotate the credential and resend without it. |
| `PreToolUse` (`Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash`) | Claude **writing a secret** into a file, or putting one in a shell command. Claude is told to read it from an environment variable instead. |

Messages name the type of secret and where it was found (file, edit number, line). They never include the value, not even partly.

## What it detects

High-confidence, prefix-anchored patterns only:

- GitHub tokens (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) and GitLab tokens (`glpat-`)
- AWS access key ids (`AKIA…`, `ASIA…`) and `aws_secret_access_key = …` values
- Private key blocks (`-----BEGIN … PRIVATE KEY-----` followed by key data)
- Slack tokens (`xoxb-`, `xoxp-`, …) and Slack webhook URLs
- Stripe live keys, Google API keys, Anthropic and OpenAI API keys, npm tokens

These are let through:

- Placeholders: values containing `EXAMPLE`, `xxxx`, `REDACTED`, `***`, `your_`, `<…>`, `dummy`, `fake`, `sample`
- AWS's documentation keys
- Low-entropy values such as `ghp_aaaa…`
- A key header with no key data after it

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install secret-guard@claude-dev-toolkit
```

Requires Python 3 (preinstalled on Linux and macOS).

## Allowlist

To let a known fake value through (for example a test fixture), add a regex per line to `.secret-guard-allow` at the repository root:

```
# fixtures for the parser tests
^AKIA0TESTFIXTURE
```

The file is found by walking up from the session's working directory to the repo root. Lines starting with `#` are comments, and invalid regexes are skipped. A better option for tests is to build fake tokens at runtime from pieces, so the repository never contains a token-shaped string.

## Fails open

Any internal error, an unreadable payload or a missing field means the call is allowed, with no message. The hook always exits 0.

## Limits

- It checks what goes **in**: your prompts, and Claude's file writes and commands. It does not filter tool **output**. A secret printed by `cat .env` still reaches the conversation. For remote logs, `aws-ssm-tools` masks output on its own.
- It is pattern-based. A password with no recognisable prefix, such as `hunter2`, is not detected.
- It cannot un-send anything. If a secret was pasted before this plugin was installed, rotate it.

## Tests

```bash
tests/run    # fake secrets generated at runtime; no token-shaped strings in the repo
```
