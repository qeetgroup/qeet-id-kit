# Changelog

All notable changes to the Qeet ID Kit. Versions follow [Semantic Versioning](https://semver.org/);
each release is tagged `vX.Y.Z` and published as `qeet-id-kit-vX.Y.Z.zip`.

## [Unreleased]

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
