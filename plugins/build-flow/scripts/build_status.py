#!/usr/bin/env python3
"""build-status: read-only progress report for a /build-plan issue tree.

Counts epic/story/task issues and lists which open tasks can start now
(every "Blocked by: #N" is closed and there is no `blocked` label).
Reads through the `gh` CLI; never writes to GitHub. Stdlib only.

Exit codes: 0 ok, 2 bad usage, 3 gh missing / not authenticated / failed.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys

BLOCKED_BY = re.compile(r"blocked by:?\s*#(\d+)", re.IGNORECASE)


class Usage(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        sys.stderr.write(f"build-status: {message}\n")
        sys.exit(2)


def die(message):
    sys.stderr.write(f"build-status: {message}\n")
    sys.exit(3)


def gh(*args):
    try:
        done = subprocess.run(["gh", *args], capture_output=True, text=True)
    except OSError as exc:
        die(f"could not run gh: {exc}")
    return done.returncode, done.stdout


def has(issue, label):
    return any(l.get("name") == label for l in issue.get("labels", []))


def counts(items):
    return {
        "open": sum(1 for i in items if i["state"] == "OPEN"),
        "closed": sum(1 for i in items if i["state"] == "CLOSED"),
    }


def build_report(repo, issues):
    state = {str(i["number"]): i["state"] for i in issues}
    tasks = [i for i in issues if has(i, "task")]
    t = counts(tasks)
    total = t["open"] + t["closed"]
    ready, waiting = [], []
    for task in (i for i in tasks if i["state"] == "OPEN"):
        blockers = [n for n in BLOCKED_BY.findall(task.get("body") or "")
                    if state.get(n) != "CLOSED"]
        if blockers or has(task, "blocked"):
            waiting.append({"number": task["number"], "title": task["title"],
                            "blockers": blockers})
        else:
            ready.append({"number": task["number"], "title": task["title"],
                          "parallel_safe": has(task, "parallel-safe")})
    return {
        "repo": repo,
        "epics": counts([i for i in issues if has(i, "epic")]),
        "stories": counts([i for i in issues if has(i, "story")]),
        "tasks": t,
        "progress": t["closed"] * 100 // total if total else 0,
        "ready": ready,
        "waiting": waiting,
    }


def render(r):
    lines = [
        f"repo={r['repo']}",
        f"epic   open={r['epics']['open']} closed={r['epics']['closed']}",
        f"story  open={r['stories']['open']} closed={r['stories']['closed']}",
        f"task   open={r['tasks']['open']} closed={r['tasks']['closed']}"
        f"  progress={r['progress']}%",
    ]
    if r["tasks"]["open"] + r["tasks"]["closed"] == 0:
        lines += ["", "No task issues found. Run /build-plan to create them."]
        return "\n".join(lines)
    lines += ["", f"ready now ({len(r['ready'])}):"]
    for i in r["ready"]:
        tag = " [parallel-safe]" if i["parallel_safe"] else ""
        lines.append(f"  #{i['number']} {i['title']}{tag}")
    lines += ["", f"waiting ({len(r['waiting'])}):"]
    for i in r["waiting"]:
        why = ", ".join(f"#{n}" for n in i["blockers"]) or "blocked label"
        lines.append(f"  #{i['number']} {i['title']} <- {why}")
    return "\n".join(lines)


def main(argv=None):
    p = Usage(prog="build-status",
              description="Progress report for a /build-plan issue tree (read-only).",
              epilog="exit codes: 0 ok, 2 bad usage, 3 gh missing or not authenticated")
    p.add_argument("--repo", help="OWNER/NAME (default: the current directory's repo)")
    p.add_argument("--milestone", help='only issues in this milestone, e.g. "Epic 1: Auth"')
    p.add_argument("--json", action="store_true", help="print JSON instead of text")
    a = p.parse_args(argv)

    if not shutil.which("gh"):
        die("gh not found; install it from https://cli.github.com")
    if gh("auth", "status")[0] != 0:
        die("gh is not authenticated; run: gh auth login")

    repo = a.repo
    if not repo:
        rc, out = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
        repo = out.strip()
        if rc != 0 or not repo:
            die("not inside a GitHub repo; pass --repo OWNER/NAME")

    args = ["issue", "list", "--repo", repo, "--state", "all", "--limit", "1000",
            "--json", "number,title,state,labels,body"]
    if a.milestone:
        args += ["--milestone", a.milestone]
    rc, out = gh(*args)
    if rc != 0:
        die(f"gh issue list failed for {repo}")
    try:
        issues = json.loads(out)
    except ValueError:
        die("gh returned output that is not JSON")

    report = build_report(repo, issues)
    print(json.dumps(report, indent=2) if a.json else render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
