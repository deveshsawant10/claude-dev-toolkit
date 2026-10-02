#!/usr/bin/env python3
"""safe-git PreToolUse hook: inspect `git push` commands before they run.

Decisions, in order:
  1. force push (--force, -f, +refspec, --mirror)        -> deny
  2. branch is behind / diverged from the remote branch  -> deny (pull --rebase first)
  3. push or delete targets a protected branch           -> ask

Design rules this script must never break:
  * Always exit 0. Any internal error, missing git, unparsable command or
    failed fetch means "allow silently" (fail open) - a guard that breaks
    unrelated Bash calls is a defect.
  * Print nothing unless there is a decision to report.
  * Never print anything from the command beyond branch and remote names.
"""
import json
import os
import shlex
import subprocess
import sys

DEFAULT_PROTECTED = ["main", "master"]
SEPARATORS = {"&&", "||", ";", "|", "&", "\n", ";;", "|&"}
# git global options that take a value as the next word.
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                       "--exec-path", "--super-prefix", "--config-env"}
# push options that take a value as the next word.
PUSH_OPTS_WITH_VALUE = {"--repo", "--receive-pack", "--exec", "-o", "--push-option"}
FORCE_LONG = {"--force", "--mirror"}
SAFE_FORCE_PREFIXES = ("--force-with-lease", "--force-if-includes")


def fetch_timeout():
    try:
        return float(os.environ.get("SAFE_GIT_FETCH_TIMEOUT", "8"))
    except ValueError:
        return 8.0


def git(cwd, *args, timeout=10):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0",
               GIT_SSH_COMMAND=os.environ.get("GIT_SSH_COMMAND", "ssh -o BatchMode=yes"))
    done = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True,
                          timeout=timeout, env=env)
    return done.returncode, done.stdout.strip()


def segments(command):
    """Split a shell command into simple-command word lists."""
    lex = shlex.shlex(command, posix=True, punctuation_chars=";&|")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = "#"
    words, out = [], []
    for tok in lex:
        if tok in SEPARATORS or tok == "\n" or set(tok) <= set(";&|\n"):
            if words:
                out.append(words)
            words = []
        else:
            words.append(tok)
    if words:
        out.append(words)
    return out


def parse_git_push(words, cwd):
    """Return (dir, push_args) if words are a `git ... push ...`, else None."""
    i = 0
    while i < len(words) and "=" in words[i] and not words[i].startswith("-") \
            and words[i].split("=", 1)[0].isidentifier():
        i += 1  # leading VAR=value assignments
    if i < len(words) and words[i] in ("command", "exec", "time", "sudo", "env"):
        i += 1
    if i >= len(words) or os.path.basename(words[i]) != "git":
        return None
    i += 1
    d = cwd
    while i < len(words) and words[i].startswith("-"):
        opt = words[i]
        if opt == "-C" and i + 1 < len(words):
            d = os.path.join(d, os.path.expanduser(words[i + 1]))
            i += 2
            continue
        if opt in GIT_OPTS_WITH_VALUE:
            i += 2
            continue
        i += 1
    if i >= len(words) or words[i] != "push":
        return None
    return d, words[i + 1:]


def analyse_push(args):
    """Split push args into flags and positionals."""
    force = False
    delete = False
    all_branches = False
    positionals = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            positionals.extend(args[i + 1:])
            break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            if name.startswith(SAFE_FORCE_PREFIXES):
                pass
            elif name in FORCE_LONG:
                force = True
            elif name == "--delete":
                delete = True
            elif name in ("--all", "--branches"):
                all_branches = True
            elif name in PUSH_OPTS_WITH_VALUE and "=" not in a:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            letters = a[1:]
            if "o" in letters:
                # -o takes a value: either attached (-ofoo) or the next word.
                before = letters.split("o", 1)[0]
                force = force or "f" in before
                delete = delete or "d" in before
                if letters.endswith("o"):
                    i += 1
            else:
                force = force or "f" in letters
                delete = delete or "d" in letters
        else:
            positionals.append(a)
        i += 1
    return force, delete, all_branches, positionals


def current_branch(d):
    rc, out = git(d, "symbolic-ref", "--quiet", "--short", "HEAD")
    return out if rc == 0 and out else None


def config(d, key):
    rc, out = git(d, "config", "--get", key)
    return out if rc == 0 and out else None


def default_remote(d, branch):
    if branch:
        for key in (f"branch.{branch}.pushRemote", "remote.pushDefault", f"branch.{branch}.remote"):
            val = config(d, key)
            if val:
                return val
    return "origin"


def short(ref):
    for prefix in ("refs/heads/", "refs/remotes/"):
        if ref.startswith(prefix):
            return ref[len(prefix):]
    return ref


def targets(d, remote_given, refspecs, all_branches, branch):
    """List of (local_src_or_None, remote_branch, forced_by_plus)."""
    out = []
    if all_branches:
        rc, listing = git(d, "for-each-ref", "--format=%(refname:short)", "refs/heads")
        for b in listing.splitlines() if rc == 0 else []:
            out.append((b, b, False))
        return out
    if not refspecs:
        if not branch:
            return out
        dst = branch
        if not remote_given or remote_given == default_remote(d, branch):
            merge = config(d, f"branch.{branch}.merge")
            mode = config(d, "push.default") or "simple"
            if merge and mode == "upstream":
                dst = short(merge)
        out.append((branch, dst, False))
        return out
    for spec in refspecs:
        plus = spec.startswith("+")
        spec = spec.lstrip("+")
        if spec.startswith("refs/tags/") or spec in ("--tags",):
            continue
        if ":" in spec:
            src, dst = spec.split(":", 1)
        else:
            src, dst = spec, spec
        if src == "HEAD":
            src = branch or "HEAD"
        if dst == "HEAD":
            dst = branch or ""
        dst = short(dst)
        out.append((src or None, dst, plus))
    return out


def protected_branches(top):
    path = os.path.join(top, ".claude", "safe-git.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        names = data.get("protectedBranches")
        if isinstance(names, list) and all(isinstance(n, str) for n in names):
            return names
    except (OSError, ValueError, AttributeError):
        pass
    return DEFAULT_PROTECTED


def is_behind(d, remote, src, dst):
    """True only when we are sure the remote branch has commits src lacks."""
    if not src or not dst:
        return False
    rc, local = git(d, "rev-parse", "--verify", "--quiet", f"{src}^{{commit}}")
    if rc != 0 or not local:
        return False
    # Fetch the remote branch into a private ref so the comparison uses exactly
    # what the remote has right now. Like any fetch, git may also refresh the
    # matching remote-tracking ref (origin/<branch>); that is intended.
    try:
        rc, _ = git(d, "fetch", "--quiet", "--no-tags", remote,
                    f"+refs/heads/{dst}:refs/safe-git/remote-tip", timeout=fetch_timeout())
    except subprocess.TimeoutExpired:
        return False
    if rc != 0:
        return False  # offline, auth problem, or the branch does not exist yet
    rc, remote_tip = git(d, "rev-parse", "--verify", "--quiet", "refs/safe-git/remote-tip")
    git(d, "update-ref", "-d", "refs/safe-git/remote-tip")
    if rc != 0 or not remote_tip or remote_tip == local:
        return False
    rc, _ = git(d, "merge-base", "--is-ancestor", remote_tip, local)
    return rc == 1


def decide(command, cwd):
    """Return (decision, reason) or None."""
    found_dir = None
    ask = None
    for words in segments(command):
        if len(words) >= 2 and words[0] == "cd":
            cwd = os.path.join(cwd, os.path.expanduser(words[1]))
            continue
        parsed = parse_git_push(words, cwd)
        if not parsed:
            continue
        d, args = parsed
        found_dir = d
        force, delete, all_branches, pos = analyse_push(args)
        remote_given = pos[0] if pos else None
        refspecs = pos[1:]
        if force or any(s.startswith("+") for s in refspecs):
            return ("deny", "safe-git: force push blocked. It can overwrite commits other people "
                    "pushed. Pull and rebase instead (git pull --rebase), then push normally. "
                    "If you really mean to rewrite the remote branch, use "
                    "--force-with-lease, or ask the user to run the push themselves.")
        rc, top = git(d, "rev-parse", "--show-toplevel")
        if rc != 0 or not top:
            continue
        branch = current_branch(d)
        remote = remote_given or default_remote(d, branch)
        protected = protected_branches(top)
        for src, dst, _ in targets(d, remote_given, refspecs, all_branches, branch):
            if delete:
                if dst in protected or (src in protected):
                    name = dst or src
                    ask = ask or ("ask", f"safe-git: this deletes protected branch '{name}' "
                                  f"on '{remote}'. Confirm only if that is intended.")
                continue
            if is_behind(d, remote, src, dst):
                return ("deny", f"safe-git: '{src}' is behind '{remote}/{dst}' (the remote has "
                        "commits you do not have), so this push would be rejected or tempt a "
                        f"force push. Run: git pull --rebase {remote} {dst} - resolve any "
                        "conflicts, re-run tests - then push again.")
            if dst in protected:
                ask = ask or ("ask", f"safe-git: this pushes directly to protected branch "
                              f"'{dst}' on '{remote}'. The usual path is a feature branch and "
                              "a pull request. Approve only if a direct push is intended.")
    if found_dir is None:
        return None
    return ask


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if payload.get("tool_name") not in (None, "Bash"):
            return
        command = (payload.get("tool_input") or {}).get("command") or ""
        if "push" not in command or "git" not in command:
            return
        cwd = payload.get("cwd") or os.getcwd()
        result = decide(command, cwd)
        if not result:
            return
        decision, reason = result
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }}))
    except Exception:  # noqa: BLE001 - fail open by design
        return


if __name__ == "__main__":
    main()
    sys.exit(0)
