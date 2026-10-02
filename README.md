# claude-dev-toolkit

Claude Code plugins for everyday engineering work: taking an idea to merged code, guarding git and secrets, working through PR reviews, writing release notes, and getting hands-on with private AWS instances.

## Install

This repository is a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Add it once, then install the plugins you want:

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install build-flow@claude-dev-toolkit
/plugin install aws-ssm-tools@claude-dev-toolkit
/plugin install safe-git@claude-dev-toolkit
/plugin install secret-guard@claude-dev-toolkit
/plugin install pr-review-loop@claude-dev-toolkit
/plugin install release-notes@claude-dev-toolkit
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| [`build-flow`](./plugins/build-flow/README.md) | Idea → requirements brief → GitHub issues (epics, stories, tasks, parallel batches) → merged PRs built with TDD and parallel subagents. |
| [`aws-ssm-tools`](./plugins/aws-ssm-tools/README.md) | Private EC2 instances over SSM with no bastion or port 22: find instances, run commands, read logs with secrets masked, port forwarding, temporary `ssh`/`scp` with auto-expiry. |
| [`safe-git`](./plugins/safe-git/README.md) | Hook on every `git push` Claude runs: blocks force pushes, fetches first and blocks pushes from a stale branch, asks before pushing to `main`/`master`. |
| [`secret-guard`](./plugins/secret-guard/README.md) | Hooks that stop a pasted token from entering the conversation and stop Claude writing tokens or keys into files or commands. |
| [`pr-review-loop`](./plugins/pr-review-loop/README.md) | Works through unresolved PR review threads: fix or push back, reply with the commit, resolve only what was fixed. |
| [`release-notes`](./plugins/release-notes/README.md) | Changelog from git history between tags, grouped by Conventional Commit type, breaking changes first. |

**[Skills guide →](./docs/skills-guide.md)** covers, for every skill: how to use it, what it saves you, and what can go wrong.

## Repository layout

```
claude-dev-toolkit/
├── .claude-plugin/marketplace.json   # marketplace manifest: lists every plugin
├── plugins/
│   ├── build-flow/
│   ├── aws-ssm-tools/
│   ├── safe-git/
│   ├── secret-guard/
│   ├── pr-review-loop/
│   └── release-notes/
├── docs/                             # skills guide and design notes
└── .github/workflows/ci.yml          # validates manifests, runs tests + shellcheck
```

## Development

```bash
claude plugin validate --strict .                   # marketplace manifest
claude plugin validate --strict plugins/<name>      # one plugin
plugins/<name>/tests/run                            # tests + shellcheck
(cd plugins/<name> && claude plugin eval . --runs 1)  # does the skill trigger, and help? (costs tokens)
```

Eval cases live in `plugins/<name>/evals/<case>/`. Each case is a prompt plus graders that check the right skill fired, and an LLM judge for the answer. Every case also runs once without the plugin, so the report shows how much the plugin adds.

To try local changes before pushing, add your checkout as a marketplace:

```
/plugin marketplace add ./path/to/claude-dev-toolkit
```

## License

MIT. See [LICENSE](./LICENSE).
