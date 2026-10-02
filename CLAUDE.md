# claude-dev-toolkit

A Claude Code plugin marketplace. Each plugin lives in `plugins/<name>/` and is listed in `.claude-plugin/marketplace.json`.

## Rules

1. **New plugin:** add `plugins/<name>/.claude-plugin/plugin.json`, a README and a LICENSE, then add an entry to `marketplace.json`. The `name` must match in both places.
2. **Bump `version` in `plugin.json`** on every user-visible change. Installed copies only update when the version changes.
3. **Logic goes in scripts, not in skill prose.** Anything deterministic (API calls, parsing, counting) belongs in `scripts/` with tests. Skills decide *when* and *why*.
4. **`bin/` holds thin PATH shims only.** Claude Code adds each installed plugin's `bin/` to PATH; a shim just `exec`s the real script.
5. **Tests never touch the network.** Fake external CLIs in `tests/stub/`.
6. **Before committing:** run `claude plugin validate --strict` on the marketplace and the plugin, and run `plugins/<name>/tests/run`. CI runs the same checks.
7. **Skills get evals.** Add a trigger case and a should-not-trigger case under `plugins/<name>/evals/` for every new skill. They cost tokens, so CI does not run them; run them before a release.
8. **No company-internal content.** This repository is public: no customer names, internal hostnames, account IDs or credentials in skills, tests or fixtures.
