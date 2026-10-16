# Release process: branches, release candidates, TEST → STAGING → production

**Owner:** `qeet-id-kit` (release candidates, channels and kit releases). **Applies to:**
`qeet-id-server`, `qeet-id-login`, `qeet-id-console`, `qeet-id-website`, `qeet-id-docs`.

## Environments and who tests where

```text
DEV  ──►  TEST  ──►  STAGING  ──►  PRODUCTION
```

| Environment | Purpose | Testing activity | Runs |
|---|---|---|---|
| **DEV** | Developers' own work | — | Images built from working trees |
| **TEST** | Release-candidate testing | **QA** team | The `test` channel's candidate |
| **STAGING** | Pre-production acceptance | **Product / UAT** team | The `staging` channel's candidate: the digests QA approved |
| **PRODUCTION** | Customers | — | Deployed by each application's own pipeline from `main` |

**TEST is the environment, QA is the activity**; likewise **STAGING is the environment, UAT is the
activity**. There is no "UAT environment".

DEV, TEST and STAGING are local runtime profiles of the L0 *Local* tier, run on each person's
computer by this kit. STAGING here is **not** the L0 cloud Staging tier (`*.staging.qeet.in`),
which Qeet ID does not have. The server makes the distinction explicit: `SERVICE_ENV=local` with
`SERVICE_PROFILE=dev|test|staging` (all production security gates on); production is
`SERVICE_ENV=prod`.

## Branches (application repositories)

```text
feature/*  ──PR──►  develop                                   normal development
develop    ──────►  release/x.y.z                             cut a release (in each app repo)
release/x.y.z ◄─PR── fix/*  ──PR──►  develop                  a QA/UAT bug: fix on the release
                                                              branch, then bring it to develop
release/x.y.z ──PR──►  main  ──►  tag vx.y.z + production     after QA + UAT approval
```

- **`develop` is the default branch.** Cut `release/x.y.z` with the **same product version** in
  every application repository (even one without changes, so its image carries that release).
- **No `qa`, `uat`, `testing` or `staging` branches.** Environments are selected by promotion,
  not by branch.
- Release fixes go `fix/*` → PR into `release/x.y.z`, and back into `develop` before the release
  closes.
- Only `release/x.y.z → main` merges into `main`, after QA and UAT sign-off. Each application's
  `deploy.yml` then deploys production and tags `vx.y.z`. Deploy jobs run only on `main`.

| Change | Branch from | PR into |
|---|---|---|
| Feature / normal work | `develop` | `develop` |
| Bug found by QA/UAT in the release under test | `release/x.y.z` | `release/x.y.z`, then merged back into `develop` |
| Urgent production fix | `main` | a new `release/x.y.(z+1)` (patch release, short QA) |
| Anything else into `main` | — | never |

After a release ships, merge `main` back into `develop` before cutting the next release.

### Cadence

- Cut `release/x.y.z` from a green `develop` when the version's planned work is merged (the code
  freeze), aligned with the sprint.
- Lifecycle: cut → `rc.1` → QA in TEST (fixes → `rc.N`) → promote to STAGING → UAT →
  `production-approved` → merge to `main` (deploy + `vx.y.z`) → `main` back into `develop`.
- **At most two releases in flight**: the older in UAT on STAGING, the next in QA on TEST. A fix on
  the older release is merged forward into the newer release branch and `develop`.
- **SemVer:** minor (`1.1.0`) for normal releases, patch (`1.0.1`) only for urgent production
  fixes cut from `main`, major (`2.0.0`) for breaking changes (API contract, data that needs a
  Reset).
- A cut release branch is **frozen**: only `fix/*` PRs for QA/UAT findings, never `develop`.

### Branch protection

On the GitHub Free plan, rulesets apply only to public repositories. Today `qeet-id-login`,
`qeet-id-console` and `qeet-id-website` protect `main`; the private repositories (`qeet-id-server`,
`qeet-id-docs`, `qeet-id-kit`) have no rulesets. Where available, protect `release/**` too:
no deletion or force push, pull request with one approval, required status checks (server:
`Build & test`, `Lint`, `Integration tests`, `Vulnerability scan`; the web apps: `Verify`).

## Release candidates

```text
release/x.y.z commit ──ci.yml image job──► ghcr.io/qeetgroup/<repo>:sha-<commit>      (each app repo)
                                                   │ immutable, multi-arch, labelled
publish-candidate (qeet-id-kit) ───────────────────┘
        │  provenance-checked, digest-pinned bill of materials
        ▼
ghcr.io/qeetgroup/qeet-id-release:<x.y.z-rc.N>   (immutable)  +  channel `test` ──► QA tests in TEST
```

- **Only this repository numbers candidates.** Application repositories publish commit images
  (`sha-<40-hex>`) and never compute `rc.N`. A candidate is a product-level bill of materials:
  `1.0.0-rc.2` = these exact server, login, console, website and docs digests.
- **Provenance.** `publish-candidate` refuses a component unless its image carries the right
  `org.opencontainers.image.source`, a revision label equal to the requested commit,
  `in.qeet.source-branch` = `release/<x.y.z>`, `in.qeet.release` = `<x.y.z>`, both `linux/amd64`
  and `linux/arm64`, and (server) `in.qeet.id.schema-version`. See
  [application-contract.md](application-contract.md).
- **Carry-forward.** Leave a component's commit empty to keep the one in the current `test`
  candidate (same release only). A server-only fix is one input.
- **`dataEpoch`** is inherited from the newest candidate in any channel; `reset_required` adds one.
  It never decreases. A changed epoch makes the kit refuse testers' existing data and ask for Reset.
- **`minTestKitVersion`** (the oldest kit that can run the candidate) is inherited from the
  current `test` candidate. Raise it with the `min_kit_version` input **only** when the candidate
  needs a newer kit; testers on an older kit are then told to run Update Kit. A new kit release
  alone never raises it.

## Channels and promotion

| Channel | Points to | Moved by |
|---|---|---|
| `test` | Newest candidate for QA | `publish-candidate` (automatically), or `promote-candidate target=test` (any existing candidate, i.e. a rollback) |
| `staging` | Candidate QA approved | `promote-candidate target=staging`, only the candidate `test` points to |
| `production-approved` | Candidate UAT approved | `promote-candidate target=production-approved`, only what `staging` points to. Approval, not deployment state. |
| `x.y.z` (final, immutable) | What production runs | `promote-candidate target=final`, only from `production-approved`, after production deployed it |

Every promotion re-points the **same index digest**; nothing is rebuilt between TEST and STAGING.
Promotions record their evidence (the Jira sign-off key or URL; for `final`, the deploy runs and
tags) with the actor in the run summary. Publish and promote share one concurrency group.

## The full lifecycle

```text
1  develop → release/1.1.0 in server, login, console, website, docs
2  app CI (image job) publishes sha-<commit> images for each release-branch commit
3  publish-candidate release=1.1.0 server=<sha> login=<sha> console=<sha> website=<sha> docs=<sha>
       → 1.1.0-rc.1, test → rc.1
4  QA: Start / Update → tests rc.1 in TEST
5  bug → fix/* → PR into release/1.1.0 (+ back to develop) → app CI image
6  publish-candidate release=1.1.0 server=<new sha>        (the others carried forward)
       → 1.1.0-rc.2, test → rc.2;  QA runs Update
7  QA signs off rc.2 → promote-candidate target=staging candidate=1.1.0-rc.2 evidence=QTID-123
8  UAT: Start / Update → validates the exact rc.2 digests in STAGING
9  UAT signs off → promote-candidate target=production-approved candidate=1.1.0-rc.2 evidence=QTID-130
10 release/1.1.0 → main (PR) in each repo → deploy.yml deploys + tags v1.1.0
11 production verified → promote-candidate target=final candidate=1.1.0-rc.2 evidence=<deploy runs, tags>
       → immutable BOM 1.1.0
```

```bash
gh workflow run publish-candidate.yml -R qeetgroup/qeet-id-kit \
  -f release=1.1.0 -f server=<40-hex> -f login=<40-hex> -f console=<40-hex> \
  -f website=<40-hex> -f docs=<40-hex>
gh workflow run promote-candidate.yml -R qeetgroup/qeet-id-kit \
  -f candidate=1.1.0-rc.2 -f target=staging -f evidence=QTID-123
```

## What "same artifact" means today

| Stage | Guarantee |
|---|---|
| TEST → STAGING | **Identical artifacts**: the same image digests. |
| STAGING → production **server** | Same *source revision*; production rebuilds the image in `qeet-id-server/deploy.yml`. |
| STAGING → production **login / console / website** | Same *source revision*; production is an equivalent Vercel build, not the tested container image. |

Do not describe production as running "the exact artifact UAT tested" until production promotes
the tested digests.

## Kit releases

The kit's own version (`VERSION`, tags `vX.Y.Z`) is independent of Qeet ID versions: a new
candidate never needs a new ZIP.

1. Update `VERSION` and `CHANGELOG.md`; merge to `develop`, then `develop → main`.
2. Tag `vX.Y.Z` on that `main` commit. `package.yml` checks the tag matches `VERSION`, builds the
   kit image `ghcr.io/qeetgroup/qeet-id-test-kit:X.Y.Z` (immutable; the name is kept so installed
   kits keep updating), builds and checks `qeet-id-kit-vX.Y.Z.zip`, and creates the GitHub Release.
3. A non-prerelease tag also moves `qeet-id-test-kit:stable`, which is what **Update Kit**
   installs. A kit never installs an older version than itself through `stable`.

The ZIP is `git archive` of the repository minus the `export-ignore` paths in `.gitattributes`,
plus `kit.lock` (the kit image pinned by digest). `.dockerignore` lists the same paths, so the kit
image carries exactly the ZIP's files.

## Required GitHub settings

| Setting | Where |
|---|---|
| **Manage Actions access → `qeet-id-kit`**: Write on `qeet-id-release` and `qeet-id-test-kit`; Read on `qeet-id-server`, `qeet-id-login`, `qeet-id-console`, `qeet-id-website`, `qeet-id-docs` | Each package's settings (organization packages) |
| Testers: Read on all seven packages (and on `qeet-id-kit` to download the ZIP) | Package settings, or a testers team |

Testers authenticate with a **classic** personal access token limited to `read:packages`
(GitHub Packages does not accept fine-grained tokens).

## History: the move from `qeet-id-deploy`

The kit and the candidate workflows moved here from `qeet-id-deploy` (`test-kit/`) one
environment at a time: TEST in 1.0.1, STAGING in 1.1.0, DEV in 1.2.0. On 2026-10-16 they were
removed from `qeet-id-deploy`, which is Terraform only again; `publish-candidate` and
`promote-candidate` run only here.

Testers on Test Kit 1.0.0 keep working: the state folder, package names and channels are
unchanged, candidates keep `minTestKitVersion` 1.0.0 unless one is published with a higher
`min_kit_version`, and its Update Kit installs `stable` (this kit, in a new folder).

`qeet-id-deploy`'s **Manage Actions access** on the packages is no longer used and can be removed.
