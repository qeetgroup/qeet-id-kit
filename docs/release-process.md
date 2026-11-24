# Release process: monthly releases, test copies, TEST → STAGING → production

**Owner:** `qeet-id-kit` (test copies, channels and kit releases). **Applies to:** the three
applications released together, `qeet-id-server`, `qeet-id-hosted` (the hosted login, image
`qeet-id-login`) and `qeet-id-console`. The website and the docs ship on their own and are not part
of a test copy.

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

## Branches and versions (application repositories)

Releases are monthly and named after the month they ship: `YEAR.MONTH.N`, no leading zeros
(`2027.1.0`, not `2027.01.0`).

```text
develop                 ──►  where every change lands
develop ──cut──►  release/2027.1.0       the month's release: fixes only after the cut
release/2027.1.0 ──PR──►  main  ──►  v2027.1.0 + production      after QA + UAT sign-off
main ──►  hotfix/2027.1.1 ──PR──►  main  ──►  v2027.1.1          an urgent fix to that release
```

- **One release a month, on the third Thursday.** Cut `release/YEAR.MONTH.0` in all three
  application repositories on the Monday ten days before: QA in TEST the first week, UAT in
  STAGING the second. A release that isn't ready waits for the next month.
- **A fix found in testing is made on `develop` first, then copied to the release branch**, so no
  fix is missing from the next release.
- **`main` is production.** It takes only a release or hotfix branch; each application's
  `deploy.yml` then deploys and tags `vYEAR.MONTH.N`. On release day, delete the release branch and
  merge `main` into `develop`.
- **No `qa`, `uat`, `testing` or `staging` branches.** Environments are selected by promotion, not
  by branch.

| Change | Branch from | Goes into |
|---|---|---|
| Feature / normal work | `develop` | `develop` |
| Bug found by QA/UAT in the release under test | `develop` | `develop`, then copied to `release/YEAR.MONTH.0` |
| Urgent production fix | `main` | `hotfix/YEAR.MONTH.N`, then a pull request into `main` |
| Anything else into `main` | — | never |

## Test copies (release candidates)

```text
release/2027.1.0 commit ──candidate.yml──► ghcr.io/qeetgroup/<image>:sha-<commit>   (each app repo)
                                                  │ immutable, multi-arch, labelled
publish-candidate (qeet-id-kit) ──────────────────┘
        │  provenance-checked, digest-pinned bill of materials
        ▼
ghcr.io/qeetgroup/qeet-id-release:<2027.1.0-rc.N>   (immutable)  +  channel `test` ──► QA tests in TEST
```

- **Only this repository numbers test copies.** Application repositories publish commit images
  (`sha-<40-hex>`) and never compute `rc.N`. A test copy is a product-level bill of materials:
  `2027.1.0-rc.2` = these exact server, login and console digests.
- **Provenance.** `publish-candidate` refuses a component unless its image carries the right
  `org.opencontainers.image.source` (login: `qeet-id-hosted`), a revision label equal to the
  requested commit, `in.qeet.source-branch` = `release/<version>` or `hotfix/<version>`,
  `in.qeet.release` = `<version>`, both `linux/amd64` and `linux/arm64`, and (server)
  `in.qeet.id.schema-version`. See [application-contract.md](application-contract.md).
- **Carry-forward.** Leave a component's commit empty to keep the one in the current `test`
  candidate (same release only). A server-only fix is one input.
- **`dataEpoch`** is inherited from the newest candidate in any channel; `reset_required` adds one,
  and so does a server whose `in.qeet.id.schema-version` is below an earlier candidate's (its schema
  was rebuilt from a new first migration, so existing databases can't be migrated to it; once, even
  with `reset_required`). It never decreases. A changed epoch makes the kit refuse testers' existing
  data and ask for Reset.
- **`minTestKitVersion`** (the oldest kit that can run the candidate) is inherited from the
  current `test` candidate. Raise it with the `min_kit_version` input **only** when the candidate
  needs a newer kit; testers on an older kit are then told to run Update Kit. A new kit release
  alone never raises it. Test copies from kit 1.4.0 on hold three components, so the first one
  sets `min_kit_version=1.4.0`.

## Channels and promotion

| Channel | Points to | Moved by |
|---|---|---|
| `test` | Newest candidate for QA | `publish-candidate` (automatically), or `promote-candidate target=test` (any existing candidate, i.e. a rollback) |
| `staging` | Candidate QA approved | `promote-candidate target=staging`, only the candidate `test` points to |
| `production-approved` | Candidate UAT approved | `promote-candidate target=production-approved`, only what `staging` points to. Approval, not deployment state. |
| `YEAR.MONTH.N` (final, immutable) | What production runs | `promote-candidate target=final`, only from `production-approved`, after production deployed it |

Every promotion re-points the **same index digest**; nothing is rebuilt between TEST and STAGING.
Promotions record their evidence (the sign-off issue's URL; for `final`, the deploy runs and tags)
with the actor in the run summary. Publish and promote share one concurrency group.

## The full lifecycle

```text
1  Mon: cut release/2027.1.0 from develop in server, hosted and console
2  candidate.yml publishes sha-<commit> images for each release-branch commit
3  publish-candidate release=2027.1.0 server=<sha> login=<sha> console=<sha>
       → 2027.1.0-rc.1, test → rc.1
4  QA: Start / Update → tests rc.1 in TEST
5  bug → fixed on develop → copied to release/2027.1.0 → candidate.yml image
6  publish-candidate release=2027.1.0 server=<new sha>        (the others carried forward)
       → 2027.1.0-rc.2, test → rc.2;  QA runs Update
7  QA signs off rc.2 → promote-candidate target=staging candidate=2027.1.0-rc.2 evidence=<issue URL>
8  UAT: Start / Update → validates the exact rc.2 digests in STAGING
9  UAT signs off → promote-candidate target=production-approved candidate=2027.1.0-rc.2 evidence=<issue URL>
10 Thu: release/2027.1.0 → main (PR) in each repo → deploy.yml deploys + tags v2027.1.0
11 production verified → promote-candidate target=final candidate=2027.1.0-rc.2 evidence=<deploy runs, tags>
       → immutable BOM 2027.1.0
```

```bash
gh workflow run publish-candidate.yml -R qeetgroup/qeet-id-kit \
  -f release=2027.1.0 -f server=<40-hex> -f login=<40-hex> -f console=<40-hex>
gh workflow run promote-candidate.yml -R qeetgroup/qeet-id-kit \
  -f candidate=2027.1.0-rc.2 -f target=staging -f evidence=<issue URL>
```

## What "same artifact" means today

| Stage | Guarantee |
|---|---|
| TEST → STAGING | **Identical artifacts**: the same image digests. |
| STAGING → production **server** | **Identical artifact**: `qeet-id-server/deploy.yml` copies the tested image to ECR without rebuilding it. |
| STAGING → production **login / console** | Same *source revision*; production is an equivalent Vercel build, not the tested container image. |

## Kit releases

The kit's own version (`VERSION`, tags `vX.Y.Z`) is independent of Qeet ID versions: a new
candidate never needs a new ZIP.

1. Update `VERSION` and `CHANGELOG.md`; merge to `develop`, then `develop → main`.
2. That merge releases it: `package.yml` runs on the push to `main`, tags the commit `vX.Y.Z` from
   `VERSION` (only if that tag does not exist yet, and only if it is newer than the latest tag),
   builds the kit image `ghcr.io/qeetgroup/qeet-id-test-kit:X.Y.Z` (immutable; the name is kept so
   installed kits keep updating), builds and checks `qeet-id-kit-vX.Y.Z.zip`, and creates the
   GitHub Release, all in one run (a tag pushed with the workflow's token starts no other
   workflow). A merge to `main` that leaves `VERSION` unchanged releases nothing. Pushing a
   `vX.Y.Z` tag by hand still releases.
3. A non-prerelease tag also moves `qeet-id-test-kit:stable`, which is what **Update Kit**
   installs. A kit never installs an older version than itself through `stable`.

The ZIP is `git archive` of the repository minus the `export-ignore` paths in `.gitattributes`,
plus `kit.lock` (the kit image pinned by digest). `.dockerignore` lists the same paths, so the kit
image carries exactly the ZIP's files.

## Required GitHub settings

| Setting | Where |
|---|---|
| **Manage Actions access → `qeet-id-kit`**: Write on `qeet-id-release` and `qeet-id-test-kit`; Read on `qeet-id-server`, `qeet-id-login` and `qeet-id-console` | Each package's settings (organization packages) |
| Testers: Read on those five packages (and on `qeet-id-kit` to download the ZIP) | Package settings, or a testers team |

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
