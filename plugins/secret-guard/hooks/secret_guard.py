#!/usr/bin/env python3
"""secret-guard: block secrets in prompts and in what Claude writes or runs.

  secret_guard.py prompt   UserPromptSubmit: block a prompt that contains a secret
  secret_guard.py tool     PreToolUse: deny Write/Edit/MultiEdit/NotebookEdit/Bash
                           calls whose content contains a secret

Design rules this script must never break:
  * Never print a secret value, not even partly. Messages name the type and
    the location only.
  * Always exit 0. Any internal error means "allow silently" (fail open).
  * High-confidence patterns only. A guard that cries wolf gets uninstalled.
"""
import json
import os
import re
import sys

# (name, compiled pattern). Every pattern is anchored on a vendor-specific
# prefix or structure, so ordinary code and prose does not match.
PATTERNS = [
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{50,}\b")),
    ("GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("AWS access key id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("AWS secret access key", re.compile(
        r"(?i)aws_?secret_?access_?key[\"']?\s*[:=]\s*[\"']?([A-Za-z0-9/+]{40})(?![A-Za-z0-9/+])")),
    ("private key", re.compile(
        r"-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----\s*(?:[A-Za-z-]+:[^\n]*\n\s*)*[A-Za-z0-9+/=]{40,}")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("Slack webhook URL", re.compile(r"https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]{20,}")),
    ("Stripe live key", re.compile(r"\b(?:sk|rk)_live_[A-Za-z0-9]{24,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Anthropic API key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{30,}")),
    ("OpenAI API key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}T3BlbkFJ[A-Za-z0-9_-]{20,}")),
    ("npm token", re.compile(r"\bnpm_[A-Za-z0-9]{36}\b")),
]

# Values that are documentation or tests, not secrets.
PLACEHOLDER = re.compile(r"(?i)example|x{4,}|redacted|\*{3}|your[_-]|<[^>]*>|dummy|fake|placeholder|sample")
# AWS's own documentation keys, split so this file itself is not token-shaped.
AWS_DOC_KEYS = {"AKIAIOSFODNN7" + "EXAMPLE", "wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"}


def low_entropy(value):
    """True for repeated-character fakes, e.g. a prefix followed by all zeros."""
    body = re.sub(r"^[A-Za-z]+[_-]", "", value)
    return len(set(body)) <= 4


def load_allowlist(cwd):
    """Regexes from .secret-guard-allow at the repo root (or cwd)."""
    rules = []
    d = os.path.abspath(cwd or os.getcwd())
    while True:
        path = os.path.join(d, ".secret-guard-allow")
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#"):
                            try:
                                rules.append(re.compile(line))
                            except re.error:
                                pass
            except OSError:
                pass
            break
        if os.path.isdir(os.path.join(d, ".git")):
            break
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return rules


def find_secrets(text, allow):
    """[(type, line_number)] for every secret in text, values never returned."""
    hits = []
    if not text or not isinstance(text, str):
        return hits
    for name, pattern in PATTERNS:
        for m in pattern.finditer(text):
            value = m.group(1) if m.groups() and m.group(1) else m.group(0)
            if value in AWS_DOC_KEYS or PLACEHOLDER.search(value) or low_entropy(value):
                continue
            if any(rule.search(value) for rule in allow):
                continue
            hits.append((name, text.count("\n", 0, m.start()) + 1))
    return hits


def describe(hits):
    seen = []
    for name, line in hits:
        item = f"{name} (line {line})"
        if item not in seen:
            seen.append(item)
    return ", ".join(seen)


def tool_texts(tool, inp):
    """(label, text) pairs to scan for one tool call."""
    path = inp.get("file_path") or inp.get("notebook_path") or ""
    if tool == "Write":
        return [(f"{path} (content)", inp.get("content"))]
    if tool == "Edit":
        return [(f"{path} (new text)", inp.get("new_string"))]
    if tool == "MultiEdit":
        return [(f"{path} (edit {i + 1})", e.get("new_string"))
                for i, e in enumerate(inp.get("edits") or []) if isinstance(e, dict)]
    if tool == "NotebookEdit":
        return [(f"{path} (cell source)", inp.get("new_source"))]
    if tool == "Bash":
        return [("the shell command", inp.get("command"))]
    return []


def check_tool(payload):
    tool = payload.get("tool_name") or ""
    inp = payload.get("tool_input") or {}
    allow = load_allowlist(payload.get("cwd"))
    found = []
    for label, text in tool_texts(tool, inp):
        hits = find_secrets(text, allow)
        if hits:
            found.append(f"{label}: {describe(hits)}")
    if not found:
        return None
    reason = ("secret-guard: blocked because it contains a secret - " + "; ".join(found) + ". "
              "Do not write credentials into files or commands. Read them from an environment "
              "variable or a secret manager instead (e.g. \"$GITHUB_TOKEN\"). If this is a fake "
              "test value, build it at runtime from pieces, or add a regex for it to "
              ".secret-guard-allow at the repo root.")
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def check_prompt(payload):
    allow = load_allowlist(payload.get("cwd"))
    hits = find_secrets(payload.get("prompt") or "", allow)
    if not hits:
        return None
    kinds = sorted({name for name, _ in hits})
    reason = ("secret-guard: your message was NOT sent because it contains "
              f"{' and '.join(kinds)}, so it was not added to the conversation. "
              "If that credential is real, treat it as exposed anyway (it was in your clipboard "
              "and terminal): revoke or rotate it now. Then resend the message without it - "
              "tools such as gh and aws read credentials from their own login, so Claude does "
              "not need the value.")
    return {"decision": "block", "reason": reason}


def main():
    try:
        mode = sys.argv[1] if len(sys.argv) > 1 else "tool"
        payload = json.loads(sys.stdin.read() or "{}")
        if not isinstance(payload, dict):
            return
        result = check_prompt(payload) if mode == "prompt" else check_tool(payload)
        if result:
            print(json.dumps(result))
    except Exception:  # noqa: BLE001 - fail open by design
        return


if __name__ == "__main__":
    main()
    sys.exit(0)
