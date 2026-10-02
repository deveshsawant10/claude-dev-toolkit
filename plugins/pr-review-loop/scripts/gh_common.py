"""Shared gh helpers for pr-review-loop. Stdlib only.

Exit codes: 2 bad usage, 3 gh missing / not authenticated / API error,
4 no pull request found.
"""
import json
import shutil
import subprocess
import sys


def die(tool, code, message):
    sys.stderr.write(f"{tool}: {message}\n")
    sys.exit(code)


def gh(*args):
    """Run gh; return (returncode, stdout, stderr)."""
    try:
        done = subprocess.run(["gh", *args], capture_output=True, text=True)
    except OSError as exc:
        return 127, "", str(exc)
    return done.returncode, done.stdout, done.stderr


def require_gh(tool):
    if not shutil.which("gh"):
        die(tool, 3, "gh not found; install it from https://cli.github.com")
    if gh("auth", "status")[0] != 0:
        die(tool, 3, "gh is not authenticated; run: gh auth login")


def graphql(tool, query, **variables):
    """Run a GraphQL query. String values go with -f, ints with -F."""
    args = ["api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        if value is None:
            continue
        flag = "-F" if isinstance(value, int) else "-f"
        args += [flag, f"{key}={value}"]
    rc, out, err = gh(*args)
    if rc != 0:
        die(tool, 3, f"GitHub API call failed: {err.strip() or out.strip() or 'no output'}")
    try:
        data = json.loads(out)
    except ValueError:
        die(tool, 3, "GitHub returned output that is not JSON")
    if data.get("errors"):
        die(tool, 3, "GitHub API error: " + "; ".join(e.get("message", "?") for e in data["errors"]))
    return data.get("data") or {}
