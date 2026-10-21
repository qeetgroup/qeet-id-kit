# Qeet ID Kit

Run Qeet ID on your own computer for testing, from a terminal. No source code and no developer
tools: the kit downloads the exact Qeet ID version under test and runs the whole product (server,
hosted login, console, website, docs and an email inbox) at addresses like
`https://console.test.id.qeet.in`.

| Environment | For | What runs there | In this kit |
|---|---|---|---|
| **TEST** | The **QA** team | The current release candidate | Yes |
| **STAGING** | The **Product / UAT** team | The candidate QA approved, the exact same build | Yes |
| **DEV** | Developers | Images built from their own working copies | Yes |

All three can run at the same time. Each has its own accounts, data, email inbox, passkeys and
addresses, so nothing you do in one appears in another.

> These are **local** environments on your computer. They are not shared servers, and STAGING here
> is not a cloud staging environment.

---

## 1. First-time setup (once)

1. **Install Docker and start it.**
   - macOS and Windows: [Docker Desktop](https://www.docker.com/products/docker-desktop/). On
     Windows, keep the default *Linux containers* mode.
   - Linux: Docker Engine with Docker Compose 2.24 or newer.
2. **Download the kit.** Get `qeet-id-kit-vX.Y.Z.zip` from the release your team lead shares and
   extract it in your home folder (for example `Documents`). It extracts to a folder named
   `qeet-id-kit`. Avoid OneDrive-synced folders.
3. **Open a terminal in the `qeet-id-kit` folder.** Every command below is typed there.
   - macOS: open Terminal, type `cd ` (with a space), drag the folder onto the window, press Enter.
   - Windows: open the folder in File Explorer, right-click an empty area, choose
     **Open in Terminal**.
   - Linux: `cd` to the folder.
4. **Sign in to GitHub Packages once.** You need:
   - a GitHub account that has been given access to the `qeetgroup` packages (ask your team lead);
   - a **classic** personal access token with **only** the `read:packages` scope. Create it at
     <https://github.com/settings/tokens> → **Generate new token** → **Generate new token
     (classic)**. Fine-grained tokens do not work with GitHub Packages.

   | macOS | Linux | Windows |
   |---|---|---|
   | `bash macos/tools/login.sh` | `bash linux/tools/login.sh` | `.\windows\tools\login.cmd` |

   Enter your GitHub username. Docker then asks for the token (typing is hidden) and keeps it in
   its own credential store; the kit never stores it. Login then checks that this sign-in can
   download every Qeet ID image, and tells you if it cannot.

That is all. You do not need Git, Node.js, Go, a database client or Docker commands.

> **Windows:** the commands work in PowerShell and in Command Prompt. In Command Prompt, leave out
> the leading `.\` (for example `windows\test\start.cmd`).

## 2. Start testing

| | macOS | Linux | Windows |
|---|---|---|---|
| QA: start TEST | `bash macos/test/start.sh` | `bash linux/test/start.sh` | `.\windows\test\start.cmd` |
| UAT: start STAGING | `bash macos/staging/start.sh` | `bash linux/staging/start.sh` | `.\windows\staging\start.cmd` |
| Developers: start DEV | `bash macos/dev/start.sh --build` | `bash linux/dev/start.sh --build` | `.\windows\dev\start.cmd --build` |

STAGING runs a candidate only after QA has approved it in TEST and the release manager has
promoted it. Until then, Start STAGING says *No Qeet ID candidate has been promoted to STAGING
yet*. DEV is described in [For developers: DEV](#for-developers-dev) below.

The first start downloads Qeet ID (about 1 GB) and prepares a fresh database, which takes about a
minute after the download. Then your browser opens the console. You will see something like:

```text
Qeet ID TEST

Installed: none
Available: 1.0.0-rc.1
Updating...
✓ Generated local test-only secrets
✓ Images ready
Starting TEST (first start applies every database migration — about a minute)...
✓ Database ready, migrations completed
✓ Qeet ID Server healthy
✓ Login healthy
✓ Console healthy
✓ Website healthy
✓ Docs healthy
✓ Mail inbox healthy
✓ Fresh environment: empty baseline — create accounts through Sign up

✓ Qeet ID 1.0.0-rc.1 is ready in TEST.
```

**The first TEST start also asks you once to trust the kit's certificate authority**, so your
browser accepts TEST's `https://` addresses: macOS asks for your password, Windows asks you to
choose **Yes**. It is created on your computer and can vouch only for the kit's own addresses
(see [Security](#7-security)).

### Your addresses

| | TEST | STAGING | DEV |
|---|---|---|---|
| Console (start here) | <https://console.test.id.qeet.in> | <http://console.staging.id.qeet.localhost> | <http://console.dev.id.qeet.localhost> |
| Hosted login | <https://login.test.id.qeet.in> | <http://login.staging.id.qeet.localhost> | <http://login.dev.id.qeet.localhost> |
| API | <https://api.test.id.qeet.in> | <http://api.staging.id.qeet.localhost> | <http://api.dev.id.qeet.localhost> |
| **Mail inbox** | <https://mail.test.id.qeet.in> | <http://mail.staging.id.qeet.localhost> | <http://mail.dev.id.qeet.localhost> |
| Website | <https://test.id.qeet.in> | <http://staging.id.qeet.localhost> | <http://dev.id.qeet.localhost> |
| Docs | <https://docs.test.id.qeet.in> | <http://docs.staging.id.qeet.localhost> | <http://docs.dev.id.qeet.localhost> |

The website's **Sign in** and **Start free** buttons and its documentation links open *this*
environment's console and docs. Links inside the docs that name `qeet.in` addresses (for example
in code samples) are production addresses. They are documentation, not part of the environment.

**Use Google Chrome or Microsoft Edge.** Other browsers have not been verified with the kit.

- **TEST** (`*.test.id.qeet.in`) uses real public names whose DNS points at your own computer
  (`127.0.0.1`), over `https`, so Google, Microsoft and Apple sign-in can be tested there. Each
  tester reaches their own computer; nothing goes to the internet. If the addresses do not open,
  your network may block such names; Start then shows a line to add to your hosts file
  ([troubleshooting](docs/troubleshooting.md#in-the-browser)).
- **STAGING and DEV** (`*.localhost`) open on your computer automatically.

### Test data: you start empty

Every environment starts with **no accounts and no organizations**. Create what you need the way a customer
would: **Sign up** in the console, verify your email, create your organization, invite teammates.
This is deliberate (see the QA test strategy).

Every email Qeet ID sends (verification codes, magic links, invitations, password resets) lands
in that environment's **Mail inbox**, not in a real mailbox. Use any address you like, such as
`ana@example.test`. Nothing leaves your computer.

## 3. Everyday use

The TEST commands for macOS are shown. For STAGING use `staging/` instead of `test/` (for example
`bash macos/staging/update.sh`); DEV has Start, Stop, Status, Logs and Reset (see below). On Linux
use `linux/` instead of `macos/`.

| To… | macOS / Linux | Windows |
|---|---|---|
| Get the newest candidate (after a fix) | `bash macos/test/update.sh`, or start again | `.\windows\test\update.cmd` |
| See versions, health and addresses | `bash macos/test/status.sh` | `.\windows\test\status.cmd` |
| Stop one environment (data kept) | `bash macos/test/stop.sh` | `.\windows\test\stop.cmd` |
| Stop everything (data kept) | `bash macos/tools/stop-all.sh` | `.\windows\tools\stop-all.cmd` |
| Go back to the previous candidate | `bash macos/test/rollback.sh` | `.\windows\test\rollback.cmd` |
| Start over with empty data | `bash macos/test/reset.sh` | `.\windows\test\reset.cmd` |
| See logs for a bug report | `bash macos/test/logs.sh server` | `.\windows\test\logs.cmd server` |
| Check your computer | `bash macos/tools/doctor.sh` | `.\windows\tools\doctor.cmd` |
| Free disk space (old candidates) | `bash macos/tools/cleanup.sh` | `.\windows\tools\cleanup.cmd` |
| Install a newer kit | `bash macos/tools/update-kit.sh` | `.\windows\tools\update-kit.cmd` |

**Updates.** When developers fix a bug, the release manager publishes a new candidate (for example
`1.0.0-rc.1 → rc.2`). Run **Update**, or just start the environment again. Your data is kept; only what
changed is restarted:

```text
Installed: 1.0.0-rc.1
Available: 1.0.0-rc.2
Updating...
✓ Qeet ID 1.0.0-rc.2 is ready in TEST.
```

STAGING receives a candidate only after QA approves it, so TEST and STAGING can be on different
candidates. You never download a new ZIP for a new candidate. A new ZIP is needed only when the kit itself
changes, and then **Update Kit** fetches it for you (see below).

**Rollback** returns to the previous candidate already on your computer, without downloading,
and keeps you there until you run Update. If your data was already upgraded beyond what the
older candidate understands, it refuses and tells you how to roll back with fresh data
(`rollback.sh --reset`, which deletes that environment's data).

**Reset** permanently deletes one environment's accounts, organizations and emails and starts it
fresh. It asks you to type the environment's name (`test`, `staging` or `dev`) first and never
touches the other environments. Afterwards, also delete any passkeys you saved for it (for example
`test.id.qeet.in`) in your browser or password manager.

**Update Kit** installs a newer kit in a new folder next to this one (`qeet-id-kit-X.Y.Z`) and
copies your `environments/optional.env` into it. Use the new folder from then on. Your data and GitHub sign-in
are kept.

**When you report a bug**, include the environment, the candidate shown by **Status** (for example `1.0.0-rc.1`),
the time, and the request ID from the error if one is shown. Attach the **Logs** output if it
helps. Never paste passwords, tokens or cookie values into Jira.

**Something wrong?** Run **Doctor** first. It checks Docker, memory, disk, ports 80 and 443, your
GitHub sign-in (including that it can download every image), that TEST's addresses lead to your
computer and that its certificate authority is trusted, and the kit itself, and says what to fix.
Every message the kit shows is explained in [docs/troubleshooting.md](docs/troubleshooting.md).

### For developers: DEV

DEV runs Qeet ID exactly like TEST and STAGING (behind the local router, with every production
security setting on), but from **your own code** instead of a release candidate.

| To… | macOS / Linux | Windows |
|---|---|---|
| Build all five components from your working trees and start | `bash macos/dev/start.sh --build` | `.\windows\dev\start.cmd --build` |
| Use a specific image for one component | add `--image server=<image>` (or `login=`, `console=`, `website=`, `docs=`) | same |
| Start again with the images DEV ran last time | `bash macos/dev/start.sh` | `.\windows\dev\start.cmd` |

- **Where the code comes from.** `--build` uses the repositories next to the kit folder
  (`../qeet-id-server`, `../qeet-id-login`, `../qeet-id-console`, `../qeet-id-website`,
  `../qeet-id-docs`), which is the layout of a Qeet ID workspace with the `qeet-id-kit`
  repository in it. Elsewhere, set `QEET_KIT_DEV_<COMPONENT>_SRC` in `environments/optional.env`.
  Each repository is built with its own `Dockerfile`; your working tree is only read.
- **`--image` wins over `--build`** for that component, so
  `start.sh --build --image login=<image> --image console=<image> --image website=<image> --image docs=<image>`
  builds only the server. Published CI images look like
  `ghcr.io/qeetgroup/qeet-id-server:sha-<commit>`.
- **Status** shows each component's image and commit (`-dirty` when the working tree had
  uncommitted changes). The first build of all five components takes several minutes.
- DEV has no Update or Rollback: rebuild with `--build`. If you check out an older branch whose
  database is older than DEV's data, Start refuses and tells you to **Reset** DEV.

## 4. Optional settings

Nothing needs configuring: sign-up, email, passkeys, sign-in, organizations and OIDC work as
shipped. To switch on a third-party integration (GitHub, Google or Microsoft sign-in, Razorpay test
payments, SMS, the AI assistant), fill in the values you need in `environments/optional.env` and
start the environment again. The file explains every setting, and applies to every environment alike.

- **Test credentials only.** Never put a production key, password or token there.
- Security settings and the keys the kit generates cannot be changed there.

## 5. What you cannot test locally

These need real HTTPS, public callbacks or paid third-party accounts:

- **Google, Microsoft and Apple sign-in in STAGING and DEV.** Those providers refuse `*.localhost`
  and `http` callbacks. In **TEST** (`https`) Google and Microsoft work with a test app registered
  for `https://api.test.id.qeet.in/v1/social/<provider>/callback`; Apple is not verified yet (it may
  ask to verify the domain from the internet). GitHub sign-in works everywhere with a GitHub OAuth
  app per environment (see `environments/optional.env`).
- **Stripe payments.** Stripe confirms payments only by webhook, which must be forwarded to your
  computer. Razorpay *test* payments work without a webhook. The Free plan always works.
- **SMS codes** unless you set a Twilio account in `environments/optional.env` (real, paid SMS). Use email or
  authenticator-app MFA instead.
- **Webhooks, SIEM streaming and auth hooks** to a receiver on your computer. Qeet ID blocks
  private and `*.localhost` destinations by design; a public HTTPS test receiver works.
- **SAML and SCIM in STAGING and DEV.** Some addresses the server builds itself (for example inside
  SAML metadata) start with `https://` for these hosts, a known server issue. TEST is `https`, so
  they are right there. SCIM provisioning from a cloud identity provider (Okta, Entra) still cannot
  reach your computer.
- **IP allow-lists and country rules.** Every request reaches Qeet ID from Docker's own address.
- **The Qeet ID Authenticator mobile app** (`qeet-id-auth`). It runs on a phone, and the environments
  are reachable only from this computer. It is tested separately, not with this kit.
- **Third-party apps (OIDC)** with redirect addresses other than `http://localhost:<port>/…`.
  Other `http` redirect hosts are rejected, as in production.

## 6. Computer requirements

- Docker with at least **2 GiB** of memory (Docker Desktop → Settings → Resources); 4 GiB to run
  TEST, STAGING and DEV together. Each environment itself uses about 0.5 GiB.
- About **10 GiB** of free disk.
- macOS (Apple Silicon or Intel), Windows 10/11 x64, or Linux (x64 or arm64).
- Google Chrome or Microsoft Edge.

## 7. Security

- Everything runs on your computer and listens only on `127.0.0.1`. It is not reachable from the
  network.
- No production data, accounts or secrets are used. Each environment generates its own random,
  test-only keys the first time it starts and keeps them in your user folder (`~/.qeet-id-test-kit` on
  macOS/Linux, `%LOCALAPPDATA%\QeetIdTestKit` on Windows). They are never in this folder or in the
  ZIP. Reset deletes them with the data.
- Qeet ID runs with its **production security settings** (CSRF protection, secure cookies, strict
  outbound rules); only the addresses differ.
- TEST's `https` certificates come from a **certificate authority created on your computer** the
  first time the kit starts (`edge/ca` in the state folder). It is name-constrained: it can vouch
  only for the kit's own zones (`*.test.id.qeet.in`, `*.staging.id.qeet.in`, `*.dev.id.qeet.in`),
  never for any other site, production `id.qeet.in` included. Its key never leaves the state
  folder, and Reset keeps it.

## 8. Uninstall

1. **Stop everything**: `bash macos/tools/stop-all.sh` (Windows: `.\windows\tools\stop-all.cmd`).
2. **Reset** each environment you used to delete its data, or delete every kit volume and network
   at once:

   ```text
   docker volume rm qeet-id-test-postgres qeet-id-test-mail qeet-id-staging-postgres qeet-id-staging-mail qeet-id-dev-postgres qeet-id-dev-mail
   docker network rm qeet-id-dev-edge qeet-id-test-edge qeet-id-staging-edge
   ```
3. Run **Cleanup**, then delete any remaining `qeet-id-*` images in Docker Desktop (including DEV's
   `qeet-id-*:dev` builds).
4. Delete the state folder (`~/.qeet-id-test-kit` or `%LOCALAPPDATA%\QeetIdTestKit`) and this
   kit folder, and remove the trusted *Qeet ID Kit local CA (this computer only)* certificate:
   macOS: Keychain Access → login → Certificates; Windows: `certmgr.msc` → Trusted Root
   Certification Authorities; Linux: `certutil -d sql:$HOME/.pki/nssdb -D -n "Qeet ID Kit local CA (this computer only)"`.
5. Optionally sign out: `docker logout ghcr.io`.

---

Maintainers: how the kit works and how releases move are described in `docs/` in the
`qeetgroup/qeet-id-kit` repository (not part of the ZIP).
