# Qeet ID Kit

Run Qeet ID on your own computer for testing, from a terminal. No source code and no developer
tools: the kit downloads the exact Qeet ID version under test and runs the whole product (server,
hosted login, console, website, docs and an email inbox) at addresses like
`http://console.test.id.qeet.localhost`.

| Environment | For | What runs there | In this kit |
|---|---|---|---|
| **TEST** | The **QA** team | The current release candidate | Yes |
| **STAGING** | The **Product / UAT** team | The candidate QA approved, the exact same build | Coming next |
| **DEV** | Developers | Images built from their own working copies | Coming later |

> These are **local** environments on your computer. They are not shared servers, and STAGING here
> is not a cloud staging environment.
>
> STAGING and DEV are moving here from Test Kit 1.0.0 (`qeetgroup/qeet-id-deploy`) one at a time.
> Until they arrive, keep using Test Kit 1.0.0 for them. Both kits use the same data, keys and
> GitHub sign-in on your computer, so switching between them loses nothing.

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

| macOS | Linux | Windows |
|---|---|---|
| `bash macos/test/start.sh` | `bash linux/test/start.sh` | `.\windows\test\start.cmd` |

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

### Your addresses

| | TEST |
|---|---|
| Console (start here) | <http://console.test.id.qeet.localhost> |
| Hosted login | <http://login.test.id.qeet.localhost> |
| API | <http://api.test.id.qeet.localhost> |
| **Mail inbox** | <http://mail.test.id.qeet.localhost> |
| Website | <http://test.id.qeet.localhost> |
| Docs | <http://docs.test.id.qeet.localhost> |

The website's **Sign in** and **Start free** buttons and its documentation links open *this*
environment's console and docs. Links inside the docs that name `qeet.in` addresses (for example
in code samples) are production addresses. They are documentation, not part of the environment.

**Use Google Chrome or Microsoft Edge.** They open `*.localhost` addresses on your computer
automatically. Other browsers have not been verified with the kit.

### Test data: you start empty

TEST starts with **no accounts and no organizations**. Create what you need the way a customer
would: **Sign up** in the console, verify your email, create your organization, invite teammates.
This is deliberate (see the QA test strategy).

Every email Qeet ID sends (verification codes, magic links, invitations, password resets) lands
in the **Mail inbox**, not in a real mailbox. Use any address you like, such as
`ana@example.test`. Nothing leaves your computer.

## 3. Everyday use

The macOS commands are shown; on Linux use `linux/` instead of `macos/`.

| To… | macOS / Linux | Windows |
|---|---|---|
| Get the newest candidate (after a fix) | `bash macos/test/update.sh`, or start again | `.\windows\test\update.cmd` |
| See versions, health and addresses | `bash macos/test/status.sh` | `.\windows\test\status.cmd` |
| Stop TEST (data kept) | `bash macos/test/stop.sh` | `.\windows\test\stop.cmd` |
| Stop everything (data kept) | `bash macos/tools/stop-all.sh` | `.\windows\tools\stop-all.cmd` |
| Go back to the previous candidate | `bash macos/test/rollback.sh` | `.\windows\test\rollback.cmd` |
| Start over with empty data | `bash macos/test/reset.sh` | `.\windows\test\reset.cmd` |
| See logs for a bug report | `bash macos/test/logs.sh server` | `.\windows\test\logs.cmd server` |
| Check your computer | `bash macos/tools/doctor.sh` | `.\windows\tools\doctor.cmd` |
| Free disk space (old candidates) | `bash macos/tools/cleanup.sh` | `.\windows\tools\cleanup.cmd` |
| Install a newer kit | `bash macos/tools/update-kit.sh` | `.\windows\tools\update-kit.cmd` |

**Updates.** When developers fix a bug, the release manager publishes a new candidate (for example
`1.0.0-rc.1 → rc.2`). Run **Update**, or just start TEST again. Your data is kept; only what
changed is restarted:

```text
Installed: 1.0.0-rc.1
Available: 1.0.0-rc.2
Updating...
✓ Qeet ID 1.0.0-rc.2 is ready in TEST.
```

You never download a new ZIP for a new candidate. A new ZIP is needed only when the kit itself
changes, and then **Update Kit** fetches it for you (see below).

**Rollback** returns to the previous candidate already on your computer, without downloading,
and keeps you there until you run Update. If your data was already upgraded beyond what the
older candidate understands, it refuses and tells you how to roll back with fresh data
(`rollback.sh --reset`, which deletes TEST's data).

**Reset** permanently deletes TEST's accounts, organizations and emails and starts it fresh. It
asks you to type `test` first and never touches other environments. Afterwards, also delete any
passkeys you saved for `test.id.qeet.localhost` in your browser or password manager.

**Update Kit** installs a newer kit in a new folder next to this one (`qeet-id-kit-X.Y.Z`) and
copies your `settings/.env` into it. Use the new folder from then on. Your data and GitHub sign-in
are kept.

**When you report a bug**, include the candidate shown by **Status** (for example `1.0.0-rc.1`),
the time, and the request ID from the error if one is shown. Attach the **Logs** output if it
helps. Never paste passwords, tokens or cookie values into Jira.

**Something wrong?** Run **Doctor** first. It checks Docker, memory, disk, port 80, your GitHub
sign-in (including that it can download every image) and the kit itself, and says what to fix.
Every message the kit shows is explained in [docs/troubleshooting.md](docs/troubleshooting.md).

## 4. Optional settings

Nothing needs configuring: sign-up, email, passkeys, sign-in, organizations and OIDC work as
shipped. To switch on a third-party integration (GitHub sign-in, Razorpay test payments, SMS, the
AI assistant), copy `settings/.example.env` to `settings/.env`, fill in the values you need and
start TEST again. The template explains every setting.

- **Test credentials only.** Never put a production key, password or token there.
- The kit accepts only the keys listed in `settings/.example.env`, and refuses to start (naming
  the key) if `settings/.env` contains any other.

## 5. What you cannot test locally

These need real HTTPS, public callbacks or paid third-party accounts:

- **Google, Microsoft and Apple sign-in.** Those providers refuse local `http` callbacks. GitHub
  sign-in works with a GitHub OAuth app you register (see `settings/.example.env`).
- **Stripe payments.** Stripe confirms payments only by webhook, which must be forwarded to your
  computer. Razorpay *test* payments work without a webhook. The Free plan always works.
- **SMS codes** unless you set a Twilio account in `settings/.env` (real, paid SMS). Use email or
  authenticator-app MFA instead.
- **Webhooks, SIEM streaming and auth hooks** to a receiver on your computer. Qeet ID blocks
  private and `*.localhost` destinations by design; a public HTTPS test receiver works.
- **SAML and SCIM integrations.** Some addresses the server builds itself (for example inside SAML
  metadata) start with `https://` for these hosts, a known server issue.
- **IP allow-lists and country rules.** Every request reaches Qeet ID from Docker's own address.
- **The Qeet ID Authenticator mobile app** (`qeet-id-auth`). It runs on a phone, and TEST is
  reachable only from this computer. It is tested separately, not with this kit.
- **Third-party apps (OIDC)** with redirect addresses other than `http://localhost:<port>/…`.
  Other `http` redirect hosts are rejected, as in production.

## 6. Computer requirements

- Docker with at least **2 GiB** of memory (Docker Desktop → Settings → Resources); 4 GiB to run
  TEST, STAGING and DEV together. TEST itself uses about 0.5 GiB.
- About **10 GiB** of free disk.
- macOS (Apple Silicon or Intel), Windows 10/11 x64, or Linux (x64 or arm64).
- Google Chrome or Microsoft Edge.

## 7. Security

- Everything runs on your computer and listens only on `127.0.0.1`. It is not reachable from the
  network.
- No production data, accounts or secrets are used. TEST generates its own random, test-only keys
  the first time it starts and keeps them in your user folder (`~/.qeet-id-test-kit` on
  macOS/Linux, `%LOCALAPPDATA%\QeetIdTestKit` on Windows). They are never in this folder or in the
  ZIP. Reset deletes them with the data.
- Qeet ID runs with its **production security settings** (CSRF protection, secure cookies, strict
  outbound rules); only the addresses differ.

## 8. Uninstall

1. **Stop everything**: `bash macos/tools/stop-all.sh` (Windows: `.\windows\tools\stop-all.cmd`).
2. **Reset TEST** to delete its data, or delete every kit volume and network at once:

   ```text
   docker volume rm qeet-id-test-postgres qeet-id-test-mail
   docker network rm qeet-id-dev-edge qeet-id-test-edge qeet-id-staging-edge
   ```

   If you also used STAGING or DEV (Test Kit 1.0.0), remove `qeet-id-staging-*` and `qeet-id-dev-*`
   volumes the same way.
3. Run **Cleanup**, then delete any remaining `qeet-id-*` images in Docker Desktop.
4. Delete the state folder (`~/.qeet-id-test-kit` or `%LOCALAPPDATA%\QeetIdTestKit`) and this
   kit folder.
5. Optionally sign out: `docker logout ghcr.io`.

---

Maintainers: how the kit works and how releases move are described in `docs/` in the
`qeetgroup/qeet-id-kit` repository (not part of the ZIP).
