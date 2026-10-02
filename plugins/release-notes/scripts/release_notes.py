#!/usr/bin/env python3
"""release-notes: draft release notes from git history, grouped by type.

Reads `git log --first-parent FROM..TO` (the commits that landed on the
release branch), parses Conventional Commit subjects, maps PR numbers from
squash "(#123)" and merge "Merge pull request #123" subjects, and prints
Markdown. When gh is installed and authenticated, PR labels and authors are
added; otherwise that step is skipped silently. Never writes anything.

Exit codes: 0 ok, 2 bad usage, 3 not a git repository or unknown ref.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys

TOOL = "release-notes"

CC = re.compile(r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.+)$")
SQUASH_PR = re.compile(r"\s*\(#(\d+)\)\s*$")
MERGE_PR = re.compile(r"^Merge pull request #(\d+) from \S+")
BREAKING = re.compile(r"^BREAKING[ -]CHANGE:\s*(.+)", re.MULTILINE)

GROUPS = [
    ("breaking", "⚠ Breaking changes"),
    ("feat", "Features"),
    ("fix", "Bug fixes"),
    ("perf", "Performance"),
    ("refactor", "Refactoring"),
    ("docs", "Documentation"),
    ("maint", "Maintenance"),
    ("other", "Other changes"),
]
MAINT = {"chore", "ci", "build", "test", "tests", "style", "revert"}


class Usage(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        die(2, message)


def die(code, message):
    sys.stderr.write(f"{TOOL}: {message}\n")
    sys.exit(code)


def git(*args, check=True):
    done = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and done.returncode != 0:
        die(3, f"git {' '.join(args)} failed: {done.stderr.strip()}")
    return done.returncode, done.stdout


def resolve_range(frm, to, pattern):
    if git("rev-parse", "--is-inside-work-tree", check=False)[0] != 0:
        die(3, "not inside a git repository")
    for ref in filter(None, [frm, to]):
        if git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}", check=False)[0] != 0:
            die(3, f"unknown ref: {ref}")
    if frm is None:
        # The newest tag strictly before TO: describe TO's first parent, so a
        # tagged TO (a release) compares against the previous release.
        if git("rev-parse", "--verify", "--quiet", f"{to}^", check=False)[0] == 0:
            args = ["describe", "--tags", "--abbrev=0", "--first-parent"]
            if pattern:
                args += ["--match", pattern]
            rc, out = git(*args, f"{to}^", check=False)
            frm = out.strip() if rc == 0 and out.strip() else None
    return frm, to


def read_commits(frm, to):
    rng = f"{frm}..{to}" if frm else to
    _, out = git("log", "--first-parent", "--format=%H%x1f%h%x1f%an%x1f%cs%x1f%s%x1f%b%x1e", rng)
    commits = []
    for rec in out.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        full, short, author, date, subject, body = (rec.split("\x1f") + [""] * 6)[:6]
        commits.append(parse(full, short, author, date, subject, body.strip()))
    return [c for c in commits if c]


def parse(full, short, author, date, subject, body):
    pr = None
    m = MERGE_PR.match(subject)
    if m:
        pr = int(m.group(1))
        subject = (body.splitlines() or [subject])[0].strip()
        body = "\n".join(body.splitlines()[1:])
    elif subject.startswith("Merge "):
        return None  # branch-sync merges carry no change of their own
    m = SQUASH_PR.search(subject)
    if m:
        pr = pr or int(m.group(1))
        subject = SQUASH_PR.sub("", subject)
    cc = CC.match(subject)
    ctype = cc.group("type").lower() if cc else None
    scope = (cc.group("scope") or None) if cc else None
    desc = cc.group("desc").strip() if cc else subject.strip()
    brk = BREAKING.search(body)
    breaking = bool(cc and cc.group("bang")) or bool(brk)
    if breaking:
        group = "breaking"
    elif ctype in ("feat", "fix", "perf", "refactor", "docs"):
        group = ctype
    elif ctype in MAINT:
        group = "maint"
    else:
        group = "other"
    return {
        "sha": full, "short": short, "author": author, "date": date,
        "type": ctype, "scope": scope, "description": desc, "group": group,
        "breaking": breaking, "breaking_note": brk.group(1).strip() if brk else None,
        "pr": pr, "pr_author": None, "labels": [],
    }


def enrich(commits, repo):
    """Add PR author and labels via gh. Any failure skips enrichment."""
    prs = sorted({c["pr"] for c in commits if c["pr"]})
    if not prs or not shutil.which("gh"):
        return None
    try:
        if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
            return None
        if not repo:
            done = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner",
                                   "-q", ".nameWithOwner"], capture_output=True, text=True)
            repo = done.stdout.strip() if done.returncode == 0 else ""
        if not repo:
            return None
        info = {}
        for n in prs:
            done = subprocess.run(["gh", "pr", "view", str(n), "--repo", repo,
                                   "--json", "author,labels"], capture_output=True, text=True)
            if done.returncode == 0:
                d = json.loads(done.stdout)
                info[n] = ((d.get("author") or {}).get("login"),
                           [l["name"] for l in d.get("labels", [])])
    except (OSError, ValueError, KeyError):
        return None
    for c in commits:
        if c["pr"] in info:
            c["pr_author"], c["labels"] = info[c["pr"]]
    return repo


def line(c, repo):
    scope = f"**{c['scope']}:** " if c["scope"] else ""
    ref = ""
    if c["pr"]:
        ref = f" ([#{c['pr']}](https://github.com/{repo}/pull/{c['pr']}))" if repo else f" (#{c['pr']})"
    by = f" by @{c['pr_author']}" if c["pr_author"] else ""
    text = f"- {scope}{c['description']}{ref}{by} ({c['short']})"
    if c["breaking_note"]:
        text += f"\n  - {c['breaking_note']}"
    return text


def render(frm, to, date, commits, repo):
    title = "Unreleased" if to == "HEAD" else to
    out = [f"## {title} ({date})", ""]
    since = f"since {frm}" if frm else "from the first commit"
    out += [f"_{len(commits)} change{'s' if len(commits) != 1 else ''} {since}_", ""]
    if not commits:
        out.append("No changes.")
        return "\n".join(out)
    for key, heading in GROUPS:
        items = [c for c in commits if c["group"] == key]
        if items:
            out += [f"### {heading}", ""] + [line(c, repo) for c in items] + [""]
    return "\n".join(out).rstrip()


def main(argv=None):
    p = Usage(prog=TOOL, description="Draft release notes from git history (read-only).",
              epilog="exit codes: 0 ok, 2 bad usage, 3 not a git repo or unknown ref")
    p.add_argument("from_ref", nargs="?", metavar="FROM",
                   help="start (exclusive); default: the newest tag before TO")
    p.add_argument("to_ref", nargs="?", metavar="TO", help="end (inclusive); default: HEAD")
    p.add_argument("--to", dest="to_opt", metavar="TO",
                   help="set TO while keeping the default FROM, e.g. --to v1.3.0")
    p.add_argument("--repo", help="OWNER/NAME for PR links and gh enrichment (default: from gh)")
    p.add_argument("--tag-pattern", help="only consider tags matching this glob when picking FROM, "
                   "e.g. 'v*' or 'my-plugin--v*'")
    p.add_argument("--offline", action="store_true", help="never call gh")
    p.add_argument("--json", action="store_true", help="print JSON instead of Markdown")
    a = p.parse_args(argv)

    if a.repo and not re.fullmatch(r"[\w.-]+/[\w.-]+", a.repo):
        die(2, f"--repo must be OWNER/NAME, got: {a.repo}")
    if a.to_opt and a.to_ref:
        die(2, "give TO either as the second argument or with --to, not both")
    frm, to = resolve_range(a.from_ref, a.to_opt or a.to_ref or "HEAD", a.tag_pattern)
    commits = read_commits(frm, to)
    repo = a.repo
    if not a.offline:
        repo = enrich(commits, a.repo) or a.repo
    _, date = git("log", "-1", "--format=%cs", to)
    date = date.strip()
    if a.json:
        print(json.dumps({"from": frm, "to": to, "date": date, "repo": repo,
                          "count": len(commits), "commits": commits}, indent=2, ensure_ascii=False))
    else:
        print(render(frm, to, date, commits, repo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
