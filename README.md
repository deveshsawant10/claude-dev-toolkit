# claude-dev-toolkit

Claude Code plugins for everyday engineering work: taking an idea to merged code, and getting hands-on with private AWS instances.

## Install

This repository is a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Add it once, then install the plugins you want:

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install build-flow@claude-dev-toolkit
/plugin install aws-ssm-tools@claude-dev-toolkit
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| [`build-flow`](./plugins/build-flow/README.md) | Idea → requirements brief → GitHub issues (epics, stories, tasks, parallel batches) → merged PRs built with TDD and parallel subagents. |
| [`aws-ssm-tools`](./plugins/aws-ssm-tools/README.md) | Private EC2 instances over SSM with no bastion or port 22: find instances, run commands, read logs with secrets masked, temporary `ssh`/`scp`. |

**[Skills guide →](./docs/skills-guide.md)** covers, for every skill: how to use it, what it saves you, and what can go wrong.

## Repository layout

```
claude-dev-toolkit/
├── .claude-plugin/marketplace.json   # marketplace manifest: lists every plugin
├── plugins/
│   ├── build-flow/
│   └── aws-ssm-tools/
├── docs/                             # skills guide and design notes
└── .github/workflows/ci.yml          # validates manifests, runs tests + shellcheck
```

## Development

```bash
claude plugin validate --strict .                   # marketplace manifest
claude plugin validate --strict plugins/<name>      # one plugin
plugins/<name>/tests/run                            # tests + shellcheck
```

To try local changes before pushing, add your checkout as a marketplace:

```
/plugin marketplace add ./path/to/claude-dev-toolkit
```

## License

MIT. See [LICENSE](./LICENSE).
