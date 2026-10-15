# Qeet ID Kit

Run Qeet ID on your own computer for testing — from a terminal, with no source code and no
developer tools. The kit downloads the exact Qeet ID version under test and runs the whole
product locally at addresses like `http://console.test.id.qeet.localhost`.

| Environment | Used by | Runs |
|---|---|---|
| **TEST** | The QA team | The current release candidate |
| **STAGING** | The UAT / product team | The candidate QA approved |
| **DEV** | Developers | Images built from their own code |

> **Status: being moved here from `qeetgroup/qeet-id-deploy`, one environment at a time — TEST
> first.** Until the first release from this repository, testers keep using Test Kit 1.0.0
> (`test-kit-v1.0.0` in `qeet-id-deploy`). Installed kits keep working throughout.

## Download

Each release is published as `qeet-id-kit-vX.Y.Z.zip`. Extracting it gives a folder named
`qeet-id-kit` — open a terminal in that folder.

## Layout

| Folder | What it is |
|---|---|
| `macos/`, `linux/`, `windows/` | The commands you type, per operating system and environment |
| `environments/` | One folder per environment (TEST, STAGING, DEV) |
| `settings/` | Optional settings for this computer |
| `core/` | Shared by every environment — never edited |
