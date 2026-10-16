# CLAUDE.md — qeet-id-kit

**Read [AGENTS.md](AGENTS.md) first.** It is the model-neutral instruction file and the source of
truth for this repository. This file adds only Claude-specific guidance.

Parent context: **L0** `qeetgroup/qeet-context` · **L1** `qeetgroup/qeet-id-context`.

## The things most likely to trip you up here

1. **The repository root is the kit.** Anything added at the root ships to testers unless it is
   listed as `export-ignore` in `.gitattributes` and in `.dockerignore`.
2. **Change `core/scripts/common.sh` and `core/scripts/QeetIdKit.ps1` together.** The PowerShell
   file must stay ASCII and Windows PowerShell 5.1 compatible; the shell script bash 3.2 compatible.
3. **Never read or echo secret values** — not a tester's filled-in `environments/optional.env`, not the state folder.
4. **No Claude attribution.** Commits and pull requests carry the repository owner's identity only.

## Working style

- **Read before editing.** Match the neighbouring file's shape rather than introducing an abstraction.
- **Every change covers DEV, TEST and STAGING.** The parity test and the CI smoke run exercise all three side by side.
