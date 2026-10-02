#!/usr/bin/env python3
"""pr-reply: reply to a pull request review thread, optionally resolving it.

This WRITES to GitHub: the reply is public on the pull request.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gh_common import die, graphql, require_gh  # noqa: E402

TOOL = "pr-reply"

REPLY = """
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { url }
  }
}
"""

RESOLVE = """
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
}
"""


class Usage(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        die(TOOL, 2, message)


def main(argv=None):
    p = Usage(prog=TOOL, description="Reply to a review thread (posts publicly).",
              epilog="exit codes: 0 ok, 2 bad usage, 3 gh problem")
    p.add_argument("thread_id", help="thread id from pr-comments, e.g. PRRT_kwDO...")
    p.add_argument("--body-file", required=True, help="file with the reply text ('-' for stdin)")
    p.add_argument("--resolve", action="store_true", help="also mark the thread resolved")
    a = p.parse_args(argv)

    if not re.fullmatch(r"[A-Za-z0-9_=-]+", a.thread_id):
        die(TOOL, 2, f"invalid thread id: {a.thread_id}")
    try:
        if a.body_file == "-":
            body = sys.stdin.read()
        else:
            with open(a.body_file, encoding="utf-8") as fh:
                body = fh.read()
    except OSError as exc:
        die(TOOL, 2, f"cannot read --body-file: {exc}")
    if not body.strip():
        die(TOOL, 2, "reply body is empty")

    require_gh(TOOL)
    data = graphql(TOOL, REPLY, threadId=a.thread_id, body=body.strip())
    url = ((data.get("addPullRequestReviewThreadReply") or {}).get("comment") or {}).get("url")
    if not url:
        die(TOOL, 3, "GitHub did not return the new comment")
    print(f"replied: {url}")
    if a.resolve:
        data = graphql(TOOL, RESOLVE, threadId=a.thread_id)
        ok = ((data.get("resolveReviewThread") or {}).get("thread") or {}).get("isResolved")
        if not ok:
            die(TOOL, 3, "reply posted but the thread was not resolved")
        print(f"resolved: {a.thread_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
