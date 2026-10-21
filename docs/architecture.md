# How the Qeet ID Kit works

For maintainers. Testers need only [README.md](../README.md) and
[troubleshooting.md](troubleshooting.md), the one page of this folder that ships in the ZIP; the
rest of `docs/` is repository-only.

## What runs

```text
Browser ──127.0.0.1:80/:443──► qeet-id-edge (Caddy; the ONLY published ports)
                           │ routes by Host: <svc>.<zone> (website: <zone>)
                           │   TEST https://*.test.id.qeet.in · DEV/STAGING http://*.<env>.id.qeet.localhost
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   qeet-id-dev        qeet-id-test      qeet-id-staging        one Compose project per environment
   server · login · console · website · docs · mailpit  ── on qeet-id-<env>-edge (aliases <env>-server, …)
   server · postgres · mailpit                           ── on qeet-id-<env>-private (internal: true)
```

- **`core/compose.yaml`** defines one environment. Every hostname is derived from the
  environment's `QEET_KIT_ZONE` and `QEET_KIT_SCHEME` (`environments/<env>.env`), so the same file
  and the same image digests serve DEV, TEST and STAGING. The edge's `import environment` lines
  repeat each zone and scheme; `tests/checks/check-zones.sh` keeps them in step.
- **`core/edge.compose.yaml`** is the shared edge, with its Caddyfile inline (no bind mount, so a
  kit in another folder never leaves a dangling path). It routes all three known environments,
  whichever kit started it. A stopped environment's hosts get a 503 "not running" page; unknown
  hosts get a 404 listing the environments.
- **Networks.** `qeet-id-<env>-private` is created by the environment's project and is internal;
  PostgreSQL is only there. `qeet-id-<env>-edge` is created by the kit (all three, idempotently)
  and is external to both projects. On each edge network the edge carries that environment's
  public hostnames as aliases, so server-side calls (login SSR, the console BFF) reach the same
  origin as the browser.
- **Nothing but the edge publishes a host port.** Internal ports are identical in every
  environment: postgres 5432, server 4001, the web apps 3000, Mailpit 1025/8025.

### Server mode

`SERVICE_ENV=local` with `SERVICE_PROFILE=<env>`: every production security gate on, and the
console and login hosts must be loopback names (`*.localhost`) or, over `https`, the profile's own
kit zone `<profile>.id.qeet.in` (qeet-id-server `config.Validate`, since the server change that
introduced it). Per environment: issuer `<scheme>://api.<zone>`, WebAuthn RP ID `<zone>`, CSRF
cookie domain `.<zone>`. Passkeys, cookies, sessions and issuers therefore never cross
environments, even when all three run at once.

### Addresses and https

| Environment | Zone | Scheme | Why |
|---|---|---|---|
| TEST | `test.id.qeet.in` | `https` | Public DNS points every name in the zone at `127.0.0.1`, so it reaches only the tester's computer, and Google, Microsoft and Apple accept its https sign-in callbacks (they refuse `*.localhost` and `http`). `http://` redirects to `https://`. |
| DEV, STAGING | `<env>.id.qeet.localhost` | `http` | Chrome and Edge treat `*.localhost` as this computer and as a secure context, so plain HTTP is enough for passkeys and Secure cookies. |

- **Certificates.** `core/image/ca.sh` (the edge's one-shot `ca` tool, run by Start before the
  edge) creates a per-computer CA in `$QEET_KIT_STATE_DIR/edge/ca/` (`root.crt` 0644, `root.key`
  0600). It is **name-constrained** to `test.id.qeet.in`, `staging.id.qeet.in` and `dev.id.qeet.in`,
  so even its key cannot vouch for any other site, production `id.qeet.in` included. The edge
  mounts the folder read-only and issues short-lived leaf certificates from it (Caddy
  `local_certs`, renewed automatically); it is never replaced, and Reset keeps it.
- **Trust.** Start asks once to trust `root.crt`: macOS login keychain (`security
  add-trusted-cert`, a password prompt), Windows current-user Root store (`Import-Certificate`, a
  Yes/No prompt), Linux the NSS database Chrome uses (`certutil`, if installed). It never fails a
  start; it explains how to do it by hand. Doctor reports it.
- **Server-side calls.** The console and login containers get only `root.crt`
  (`NODE_EXTRA_CA_CERTS`) and call the API by its https address through the edge alias. After
  the route checks, Start verifies that from the console (`node -e fetch(...)`).
- **DNS.** The browser needs the public records (or hosts-file lines). Start and Doctor check that
  the zone's names resolve to `127.0.0.1` and print the hosts line when they do not (networks
  with DNS-rebinding protection, offline computers).

### Isolation per environment

| Item | Name |
|---|---|
| Compose project | `qeet-id-<env>` |
| Networks | `qeet-id-<env>-private`, `qeet-id-<env>-edge` |
| Database | `qeet_id_<env>` in volume `qeet-id-<env>-postgres` |
| Mail inbox | volume `qeet-id-<env>-mail` |
| Secrets and state | `$QEET_KIT_STATE_DIR/<env>/` |

Reset `<env>` deletes only that environment's containers, volumes, secrets and data state.

### Edge lifecycle

| Action | Effect on the edge |
|---|---|
| Start `<env>` | Creates the networks if missing, brings the edge up (recreated only if its configuration changed), then the environment |
| Start another environment | Never restarts or stops the ones already running |
| Stop `<env>` | Stops only `qeet-id-<env>`; when no environment is left running, the edge stops too and ports 80 and 443 are free |
| Stop All | Stops every environment, then the edge |

## Configuration

| Source | Holds | Who edits it |
|---|---|---|
| `environments/<env>.env` | The environment's definition: release channel, passkey display name, mail sender, log level, breached-password check, seed switch. An environment exists in this kit when its file exists. | Maintainers only; ships with the kit |
| `environments/optional.env` | Optional integration keys and server tuning for every environment of this kit folder. Edited in place; committed and shipped with the server's defaults and every secret empty (CI: `tests/checks/check-optional-env.sh`). Loaded before the generated secrets and below the pinned `environment`, so it cannot change either. Update Kit carries it to the new folder. | The tester |
| `core/compose.yaml` `server.environment` | Everything security-relevant and every address, pinned per environment. A key here is not settable. | Maintainers only |
| State folder `secrets/` | DB password, JWT keys, encryption key, SAML keys: generated by `core/image/keygen.sh` at the first start | Nobody |

An unchanged `environments/optional.env` gives the server exactly its built-in defaults: empty
values mean "off", and every number or duration carries the default because the server refuses an
empty one.

## How Start works

1. Check the environment exists and Docker is usable (preflight).
2. Fetch the channel's release record `ghcr.io/qeetgroup/qeet-id-release:<channel>` (labels only;
   never executed) into `candidate.env`. If the registry is unreachable and a version is installed,
   start the installed one with a warning.
3. Guards, before anything changes: minimum kit version, data epoch, the database's
   `schema_migrations` against the candidate's schema, an unfinished migration, keys present for
   existing data.
4. Generate secrets if missing (the kit image runs `keygen.sh`).
5. `docker compose pull` (registry errors are classified: authentication, not found, credential
   helper, rate limit, other), bring up the edge, then `up --wait`.
6. On failure, report each service's health and the server's own refusal or migration error, and
   stop the server so it does not crash-loop.
7. Check every route through the edge, check the server logged SMTP delivery to Mailpit, record
   `current.env` / `previous.env` / `data.env`, print the addresses and open the console.

Per-environment state in `$QEET_KIT_STATE_DIR/<env>/`: `current.env` and `previous.env` (installed
releases), `candidate.env` (the last one fetched), `data.env` (cache of data epoch and schema),
`pinned` (after Rollback), `secrets/` (mode 600).

### DEV

DEV follows no channel: step 2 is replaced by a local release record (`dev_release` /
`New-DevRelease`) with version `dev`, written to `candidate.env` and, after a successful start,
`current.env`:

- `--image <component>=<ref>` uses that image (pulled if missing); its revision and, for the
  server, schema version come from the image labels.
- otherwise `--build` builds `qeet-id-<component>:dev` from `QEET_KIT_DEV_<COMPONENT>_SRC`
  (`environments/optional.env`) or `../qeet-id-<component>` next to the kit folder, with the
  repository's own `Dockerfile`, for this computer's platform only. The revision is the checkout's
  commit (`-dirty` with uncommitted changes); the server's schema version is its highest
  migration number.
- with neither, each component keeps the image DEV ran last time.

Image references may be tags (not digests) in DEV only. The data-epoch check does not apply;
the schema check does, so an older checkout than DEV's data is refused (Reset DEV). DEV has no
Update or Rollback.

## Commands and options

`kit_main <command> …` in `core/scripts/common.sh`, and `QeetIdKit.ps1 <command> …` on Windows.
The launchers in `macos/`, `linux/` and `windows/` only add the command and environment.

| Option | Use |
|---|---|
| `--verbose` (or `QEET_KIT_DEBUG=1`) | Print every Docker command and its output |
| `--candidate 1.0.0-rc.2` | Run a specific published candidate instead of the channel |
| `--manifest file.env` | Run a local release file (engineering only; tag-only image refs allowed) |
| `--yes`, `--no-browser` | Non-interactive use (CI) |
| `rollback --reset` | Roll back with fresh data |
| `logs [service] --follow --tail N` | Services: `server login console website docs db mail edge` |
| `QEET_KIT_REGISTRY`, `QEET_KIT_STATE_DIR`, `QEET_KIT_WAIT_SECONDS` | Another registry (e.g. a local one), state folder, start timeout (default 300 s) |

Underlying Docker commands, from the kit folder:

```bash
export QEET_KIT_ENV=test QEET_KIT_STATE_DIR=~/.qeet-id-test-kit
docker compose -p qeet-id-test --project-directory . -f core/compose.yaml \
  --env-file environments/test.env --env-file ~/.qeet-id-test-kit/test/current.env ps
docker compose -p qeet-id-edge --project-directory . -f core/edge.compose.yaml logs -f
```

## Tests

| Test | What it proves | Where |
|---|---|---|
| Repository hygiene | No env files, keys, kit state or release output tracked | `tests/checks/check-tracked-files.sh` |
| Parity | bash and PowerShell issue identical Docker commands for Start, Stop, Reset and Stop All across DEV, TEST and STAGING (fake `docker`) | `tests/parity/` |
| Package | The ZIP holds exactly the kit, nothing secret, correct line endings, executable scripts, a digest-pinned `kit.lock` | `tests/checks/check-package.sh` |
| Smoke | A running environment answers on every address through the edge, has the right issuer, publishes no ports | `tests/smoke/check.sh [env]`; CI runs it on demand (`validate` → `smoke_candidate`) |

## Maintaining the kit

- **Change `core/scripts/common.sh` and `core/scripts/QeetIdKit.ps1` together.** CI fails if they
  issue different Docker commands. PowerShell stays ASCII and Windows PowerShell 5.1 (and
  Constrained Language Mode) compatible; bash stays 3.2 compatible.
- Under `set -o pipefail`, never pipe Docker output into an early-exit reader (`grep -q`, `head`)
  inside a condition: Docker exits 255 on the closed pipe. Capture first, then match.
- Infrastructure images (Caddy, PostgreSQL, Mailpit, Alpine) are pinned by tag **and** digest;
  bump them deliberately. Docker's official images come from `mirror.gcr.io/library/` (Google's
  mirror of them, no sign-in): Amazon's public registry limits unsigned downloads per network
  address, which shared CI machines and office networks kept exhausting. The digest pins make the
  content identical whichever registry serves it.
- Anything added at the repository root ships to testers unless it is `export-ignore` in
  `.gitattributes` **and** listed in `.dockerignore`.
- **Every change applies to DEV, TEST and STAGING.** The parity scenario (`tests/parity/run.sh`)
  and the CI smoke run cover all three side by side; `tests/checks/check-package.sh` lists each
  environment's required files.
- Releasing a kit version: [release-process.md](release-process.md#kit-releases).
