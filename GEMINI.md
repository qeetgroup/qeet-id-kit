# GEMINI.md — qeet-id-kit

**Read [AGENTS.md](AGENTS.md) first.** It is the model-neutral instruction file and the source of
truth for this repository. This file is a pointer and adds no architecture.

Parent context: **L0** `qeetgroup/qeet-context` · **L1** `qeetgroup/qeet-id-context`.

## Non-negotiables

1. **Nothing secret is ever committed or shipped** — secrets are generated per computer.
2. **The repository root is the kit;** repository-only paths are `export-ignore` and in `.dockerignore`.
3. **`core/scripts/common.sh` and `core/scripts/QeetIdKit.ps1` change together** (parity test).
4. **Never touch production.**
