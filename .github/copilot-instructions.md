# GitHub Copilot — qeet-id-kit

**Canonical instructions: [`AGENTS.md`](../AGENTS.md).** This file is a summary; it adds no
architecture.

## Repository

The **Qeet ID Kit**: local DEV / TEST / STAGING Docker environments run from a terminal by
developers, QA and UAT, and the product release-candidate channels. The repository root is the kit;
the release ZIP is `git archive` of it minus the `export-ignore` paths.

Context: **L0** `qeet-context` (organization) → **L1** `qeet-id-context` (product) → **L2** this
repository.

## Rules

- Nothing secret is ever committed or shipped.
- `core/scripts/common.sh` and `core/scripts/QeetIdKit.ps1` change together.
- Never touch production.
