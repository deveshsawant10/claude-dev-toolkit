# pr-review-loop

Address pull request review feedback without losing track of threads: list what is unresolved, fix what is right, push back where it is not, reply with the commit, and resolve only what was fixed.

## Install

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install pr-review-loop@claude-dev-toolkit
```

Then ask Claude "address the review comments on this PR". The `review-loop` skill takes it from there. It shows you its plan and its draft replies before pushing or posting anything.

## Requirements

- [`gh`](https://cli.github.com), authenticated (`gh auth login`) with the `repo` scope.
- Python 3.

## Commands

```bash
pr-comments                     # unresolved threads on the current branch's PR
pr-comments 123 --repo o/r      # a specific PR
pr-comments --all               # include resolved threads
pr-comments --json              # machine-readable

pr-reply PRRT_kwDO… --body-file reply.md            # post a reply (public)
pr-reply PRRT_kwDO… --body-file reply.md --resolve  # reply and resolve
echo "Fixed in abc1234." | pr-reply PRRT_kwDO… --body-file -
```

Example output:

```
pr=#42 repo=acme/widgets state=OPEN branch=42-login
unresolved=2 total=3

[1] PRRT_one  src/auth.py:17
    @alice: This leaks the session token in logs.
      Please mask it.
    @bob: Agreed
    https://github.com/acme/widgets/pull/42#discussion_r1

[2] PRRT_three  src/old.py:9  (outdated)
    @ghost: Why not reuse helper()?
    https://github.com/acme/widgets/pull/42#discussion_r4
```

`pr-comments` is read-only. `pr-reply` posts publicly under your account.

Exit codes: `0` ok · `2` bad usage · `3` gh missing, not authenticated, or API error · `4` no pull request found.

## Limits

- Covers line-level review threads, not top-level PR conversation comments (use `gh pr view --comments` for those).
- Reads up to 50 comments per thread. Thread count is unlimited (paginated).

## Tests

```bash
tests/run   # fake gh, no network, plus shellcheck
```
