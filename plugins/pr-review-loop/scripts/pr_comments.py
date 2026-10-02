#!/usr/bin/env python3
"""pr-comments: list a pull request's review threads, unresolved first.

Read-only. Prints each thread's id (for pr-reply), file:line, whether it
is outdated, and every comment in it.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gh_common import die, gh, graphql, require_gh  # noqa: E402

TOOL = "pr-comments"

QUERY = """
query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number title url state headRefName
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 50) {
            nodes { id url body createdAt author { login } }
          }
        }
      }
    }
  }
}
"""


class Usage(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        die(TOOL, 2, message)


def resolve_repo(repo):
    if repo:
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
            die(TOOL, 2, f"--repo must be OWNER/NAME, got: {repo}")
        return repo
    rc, out, _ = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
    if rc != 0 or not out.strip():
        die(TOOL, 3, "not inside a GitHub repo; pass --repo OWNER/NAME")
    return out.strip()


def resolve_pr(pr, repo):
    if pr is not None:
        return pr
    rc, out, _ = gh("pr", "view", "--repo", repo, "--json", "number", "-q", ".number")
    if rc != 0 or not out.strip().isdigit():
        die(TOOL, 4, "no pull request for the current branch; pass a PR number")
    return int(out.strip())


def fetch(repo, number):
    owner, name = repo.split("/", 1)
    threads, cursor, pr = [], None, None
    while True:
        data = graphql(TOOL, QUERY, owner=owner, name=name, number=number, cursor=cursor)
        pr = (data.get("repository") or {}).get("pullRequest")
        if not pr:
            die(TOOL, 4, f"pull request #{number} not found in {repo}")
        page = pr["reviewThreads"]
        threads += page["nodes"]
        if not page["pageInfo"]["hasNextPage"]:
            break
        cursor = page["pageInfo"]["endCursor"]
    return pr, threads


def shape(thread):
    return {
        "id": thread["id"],
        "resolved": thread["isResolved"],
        "outdated": thread["isOutdated"],
        "path": thread.get("path"),
        "line": thread.get("line") or thread.get("originalLine"),
        "comments": [
            {
                "id": c["id"],
                "author": (c.get("author") or {}).get("login") or "ghost",
                "body": c.get("body") or "",
                "url": c.get("url"),
                "created_at": c.get("createdAt"),
            }
            for c in thread["comments"]["nodes"]
        ],
    }


def render(repo, pr, shown, unresolved, total):
    lines = [
        f"pr=#{pr['number']} repo={repo} state={pr['state']} branch={pr['headRefName']}",
        f"unresolved={unresolved} total={total}",
    ]
    if not shown:
        lines += ["", "No unresolved review threads."]
    for n, t in enumerate(shown, 1):
        where = f"{t['path']}:{t['line']}" if t["path"] else "(general)"
        flags = []
        if t["outdated"]:
            flags.append("outdated")
        if t["resolved"]:
            flags.append("resolved")
        tag = f"  ({', '.join(flags)})" if flags else ""
        lines += ["", f"[{n}] {t['id']}  {where}{tag}"]
        for c in t["comments"]:
            body = c["body"].strip().splitlines() or [""]
            lines.append(f"    @{c['author']}: {body[0]}")
            lines += [f"      {b}" for b in body[1:]]
        if t["comments"]:
            lines.append(f"    {t['comments'][0]['url']}")
    return "\n".join(lines)


def main(argv=None):
    p = Usage(prog=TOOL, description="List a pull request's review threads (read-only).",
              epilog="exit codes: 0 ok, 2 bad usage, 3 gh problem, 4 no pull request")
    p.add_argument("pr", nargs="?", type=int, help="PR number (default: the current branch's PR)")
    p.add_argument("--repo", help="OWNER/NAME (default: the current directory's repo)")
    p.add_argument("--all", action="store_true", help="include resolved threads")
    p.add_argument("--json", action="store_true", help="print JSON instead of text")
    a = p.parse_args(argv)

    require_gh(TOOL)
    repo = resolve_repo(a.repo)
    number = resolve_pr(a.pr, repo)
    pr, raw = fetch(repo, number)
    threads = [shape(t) for t in raw]
    unresolved = [t for t in threads if not t["resolved"]]
    shown = threads if a.all else unresolved
    if a.json:
        print(json.dumps({"repo": repo, "number": pr["number"], "title": pr["title"],
                          "url": pr["url"], "state": pr["state"], "branch": pr["headRefName"],
                          "unresolved": len(unresolved), "total": len(threads),
                          "threads": shown}, indent=2))
    else:
        print(render(repo, pr, shown, len(unresolved), len(threads)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
