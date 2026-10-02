# claude-dev-toolkit

Claude Code plugins for taking an idea from requirements to merged code.

## Install

This repository is a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins). Add it once, then install the plugins you want:

```
/plugin marketplace add deveshsawant10/claude-dev-toolkit
/plugin install build-flow@claude-dev-toolkit
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| [`build-flow`](./plugins/build-flow/README.md) | Idea → requirements brief → GitHub issues (epics, stories, tasks, parallel batches) → merged PRs built with TDD and parallel subagents. |

## Repository layout

```
claude-dev-toolkit/
├── .claude-plugin/marketplace.json   # marketplace manifest: lists every plugin
├── plugins/
│   └── build-flow/                   # one folder per plugin
├── docs/                             # design notes
└── .github/workflows/ci.yml          # validates manifests, runs tests + shellcheck
```

## Development

```bash
claude plugin validate --strict .                     # marketplace manifest
claude plugin validate --strict plugins/build-flow    # plugin manifest + skills
plugins/build-flow/tests/run                          # tests + shellcheck
```

To try local changes before pushing, add your checkout as a marketplace:

```
/plugin marketplace add ./path/to/claude-dev-toolkit
```

## License

MIT. See [LICENSE](./LICENSE).
