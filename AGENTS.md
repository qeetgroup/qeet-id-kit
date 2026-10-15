# AGENTS.md — qeet-id-kit

**The model-neutral instruction file for coding agents.** [CLAUDE.md](CLAUDE.md),
[GEMINI.md](GEMINI.md) and [.github/copilot-instructions.md](.github/copilot-instructions.md) point
here and add nothing architectural.

## What this repository is

The **Qeet ID Kit**: local DEV / TEST / STAGING Docker environments that developers, QA and UAT run
on their own computers, from a terminal, plus the product release-candidate channels
(`ghcr.io/qeetgroup/qeet-id-release`). These are Local-tier runtime profiles — never production,
never a cloud staging tier.

**The repository root is the kit.** The release ZIP (`qeet-id-kit-vX.Y.Z.zip`, extracting to
`qeet-id-kit/`) is `git archive` of the root minus the `export-ignore` paths in `.gitattributes`.

> **Migration in progress** from `qeetgroup/qeet-id-deploy` (`test-kit/`), one environment at a
> time: TEST first, then STAGING, then DEV. Until the first release from here, `qeet-id-deploy`
> remains the source of Test Kit 1.0.0.

## Context hierarchy

```text
qeet-context (L0)  →  qeet-id-context (L1)  →  qeet-id-kit (L2 — this repository)
                                            └─ runs images published by qeet-id-server, -login,
                                               -console, -website, -docs
```

## Layout

```text
README.md  TROUBLESHOOTING.md  CHANGELOG.md  VERSION     shipped — tester-facing
core/            compose.yaml, edge.compose.yaml, image/, scripts/{common.sh, QeetIdKit.ps1}
environments/    <env>/environment.env — an environment exists when its folder exists
settings/        .example.env (tracked); a tester's .env (never tracked, never shipped)
macos/ linux/    <env>/*.sh and tools/*.sh — thin launchers over core/scripts/common.sh
windows/         <env>/*.cmd and tools/*.cmd — thin launchers over core/scripts/QeetIdKit.ps1
release/  tests/  docs/  .github/                         repository only (export-ignore)
```

## Rules

1. **Nothing secret is ever committed or shipped.** Secrets are generated per computer at first
   start and kept in the user's state folder; a tester's `settings/.env` is gitignored and
   excluded from the ZIP and the kit image.
2. **Logic lives once.** `core/scripts/common.sh` (bash 3.2, macOS and Linux) and
   `core/scripts/QeetIdKit.ps1` (Windows PowerShell 5.1, ASCII only) must issue identical Docker
   commands — the parity test diffs them. Launchers stay a few lines.
3. **Terminal only.** No double-click launchers; Windows uses `.cmd` files run from PowerShell or
   Command Prompt.
4. **Keep the ZIP and the kit image identical.** `.gitattributes` (export-ignore) and
   `.dockerignore` list the same repository-only paths.
5. **Candidates are immutable; only this repository numbers them.** `x.y.z-rc.N` and final `x.y.z`
   tags are never overwritten; channels move only by digest, `test → staging →
   production-approved → final`.
6. **Never touch production.** Nothing here deploys, reads production secrets or changes Terraform.
7. **Compatibility.** Package names (`qeet-id-test-kit`, `qeet-id-release`, the app images) and
   the per-user state folder (`~/.qeet-id-test-kit`, `%LOCALAPPDATA%\QeetIdTestKit`) stay
   unchanged, so installed kits keep working.

## Escalate rather than proceed

A secret in a tracked file · a change to a package name, channel or the state folder · overwriting
a candidate or release tag · anything that touches production or another repository.
