# Changelog

All notable changes to the Qeet ID Kit. Versions follow [Semantic Versioning](https://semver.org/);
each release is tagged `vX.Y.Z` and published as `qeet-id-kit-vX.Y.Z.zip`.

## [Unreleased]

### Added

- The console and the hosted login relay the person's address to the server with a generated
  relay key (`relay.env`: `RELAY_KEYS` for the server, `QEET_ID_RELAY_KEY` for the two apps), so
  per-address limits, lockouts and audit records name the person rather than the app's server
  (QTID-828). An environment created by an earlier kit gets the key at its next Start and keeps
  its data. Releases whose images predate the relay ignore it.

### Changed

- This repository is the only source of the kit: `test-kit/` and the kit and candidate workflows
  were removed from `qeet-id-deploy`.

## [1.2.0] - 2026-10-16

Adds DEV: all three environments are now in this kit.

### Added

- **DEV**, where developers run Qeet ID from their own code: `macos/dev/`, `linux/dev/` and
  `windows/dev/` (Start, Stop, Status, Logs, Reset). `start --build` builds the components from
  the repositories next to the kit folder (or `QEET_KIT_DEV_<COMPONENT>_SRC`); `--image
  <component>=<image>` picks an image instead. All three environments run side by side. Test Kit
  1.0.0 is no longer needed.
- The parity test and the CI smoke run cover DEV.

### Changed

- DEV's start message no longer says "local build" when DEV runs chosen images.

## [1.1.0] - 2026-10-16

Adds STAGING. DEV stays in Test Kit 1.0.0 until it moves here.

### Added

- **STAGING**, where Product/UAT validates the candidate QA approved: `macos/staging/`,
  `linux/staging/` and `windows/staging/` commands. TEST and STAGING run side by side, each with its
  own accounts, data, mail inbox, passkeys and addresses.
- CI checks that `environments/optional.env` is committed without secret values. The manual smoke
  run starts TEST and STAGING together.

### Changed

- Environment definitions are `environments/test.env` and `environments/staging.env` (no folder
  per environment).
- Optional settings live in `environments/optional.env` and are edited in place; the `settings/`
  folder is gone. Update Kit carries the file to the new kit folder. **Upgrading from 1.0.1:** copy
  any values from your old `settings/.env` into `environments/optional.env`; the kit warns while a
  `settings/.env` is still there.
- The kit no longer refuses unknown keys in the optional settings. Security settings and generated
  keys still cannot be changed there: the kit's own values always win.
- Clearer messages when nothing has been promoted to STAGING yet, and when Start falls back to the
  installed version.
- PostgreSQL, Caddy and Alpine download from `mirror.gcr.io` (Google's mirror of Docker's official
  images) instead of Amazon's public registry, whose per-network download limit kept failing
  first starts and CI. Same digests, so the same content.

## [1.0.1] - 2026-10-16

The first release from `qeetgroup/qeet-id-kit`, with TEST. STAGING and DEV stay in Test Kit 1.0.0
until they move here.

### Added

- Repository `qeetgroup/qeet-id-kit`: the kit moves here from `qeetgroup/qeet-id-deploy`
  (`test-kit/`), one environment at a time, starting with TEST.
- Terminal commands per operating system and environment (`macos/`, `linux/`, `windows/`).
- Login checks that the new sign-in can actually download Qeet ID (the release channel, every
  component image and the kit image), not only that the token is valid. Doctor runs the same check.
- `README.md` is a complete tester guide; `docs/troubleshooting.md` (shipped in the ZIP) explains
  every message the kit shows.
- `tests/smoke/check.sh`: checks a running environment through the local edge (every address, the
  OIDC issuer, no published ports). The manual CI smoke run uses it.
- `publish-candidate` input `min_kit_version`, to raise the kit version a candidate needs.

### Changed

- Optional settings: `settings/.example.env` (copied to `settings/.env`) lists every server
  setting a tester may set, with its default. The keys the kit accepts are read from it.
- A candidate's minimum kit version is inherited from the current `test` candidate instead of
  being the publishing kit's version, so a new kit release never locks out testers on an older kit.
- Update Kit installs only a newer kit through `stable`, never an older one.
- Login asks for a classic token and no longer mentions SSO.
- Candidate records are labelled as built by `qeet-id-kit`.

### Fixed

- A false "Email is not being delivered to the Mail inbox" warning on every start (macOS, Linux).
- A registry rate limit ("too many requests") is reported as such, including for the edge image,
  instead of "the local edge did not start".
- A broken Docker credential helper is reported as such, instead of "not published".
- A first start that failed before the database was migrated no longer blocks the next start, and
  Logs works after it.
- When the server refuses its configuration, the whole reason is shown, not only its first line.

## [1.0.0] - 2026-10-02

Released from `qeetgroup/qeet-id-deploy` as `test-kit-v1.0.0`: local DEV, TEST and STAGING
environments with release-candidate channels.
