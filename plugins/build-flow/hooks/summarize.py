#!/usr/bin/env python3
"""Turn `build_status.py --json` output (stdin) into SessionStart hook JSON.

Prints nothing when there is nothing worth telling the session.
"""
import json
import sys

MAX_READY = 5


def summary(r):
    t = r["tasks"]
    total = t["open"] + t["closed"]
    if total == 0:
        return None
    lines = ["build-flow: %s plan is %d%% done (tasks %d/%d closed; open epics %d, open stories %d)."
             % (r["repo"], r["progress"], t["closed"], total, r["epics"]["open"], r["stories"]["open"])]
    ready = r["ready"]
    if ready:
        lines.append("Ready to start now (%d):" % len(ready))
        for i in ready[:MAX_READY]:
            tag = " [parallel-safe]" if i.get("parallel_safe") else ""
            lines.append("  #%s %s%s" % (i["number"], i["title"], tag))
        if len(ready) > MAX_READY:
            lines.append("  ... and %d more (run build-status)" % (len(ready) - MAX_READY))
        lines.append("To build them: /execute-build. Do not start building unless the user asks.")
    elif t["open"]:
        lines.append("No task is ready: %d waiting on blockers. Run build-status for details."
                     % len(r["waiting"]))
    else:
        lines.append("All tasks are closed.")
    return "\n".join(lines)


def main():
    try:
        text = summary(json.load(sys.stdin))
    except Exception:
        return 0
    if text:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": text}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
