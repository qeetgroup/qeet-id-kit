# Application image contract

**Applies to:** `qeet-id-server`, `qeet-id-login`, `qeet-id-console`, `qeet-id-website`,
`qeet-id-docs`. **Consumed by:** `publish-candidate` and the kit.

Every application that runs in DEV, TEST or STAGING provides a container image meeting this
contract. Production deployment is unaffected by it (server: ECR via `deploy.yml`; login, console
and website: Vercel).

## Publishing

| Requirement | Detail |
|---|---|
| Registry / name | `ghcr.io/qeetgroup/<repository>` |
| Tag | `sha-<full 40-hex commit>` only, **immutable**; a re-run never moves it. No `rc.N`, no `latest`. |
| When | `ci.yml` job `image`: push to `release/**`, **after every CI gate passes** |
| Platforms | `linux/amd64` and `linux/arm64` (one index) |
| Labels (config and index annotation) | `org.opencontainers.image.source` = `https://github.com/qeetgroup/<repository>` · `org.opencontainers.image.revision` = commit · `org.opencontainers.image.version` = `x.y.z` · `org.opencontainers.image.created` · `in.qeet.release` = `x.y.z` · `in.qeet.source-branch` = `release/x.y.z` · server only: `in.qeet.id.schema-version` = highest migration number |
| Workflow security | Actions pinned by commit SHA; job permissions `contents: read`, `packages: write` only |
| Package access | **Manage Actions access → `qeet-id-kit`: Read**, so `publish-candidate` can inspect it |

## Runtime

| | Server | Login | Console | Website | Docs |
|---|---|---|---|---|---|
| Port | 4001 | 3000 | 3000 | 3000 | 3000 |
| User | non-root (distroless `nonroot`) | non-root (`node`) | non-root (`node`) | non-root (`node`) | non-root (`node`) |
| Health | `/qeet-id-server healthcheck` (→ `/readyz` = 200) | `GET /healthz` = 200 JSON `{status, service, version, revision}` | same as login | same as login | same as login |
| Runtime configuration | env (`SERVICE_ENV=local`, `SERVICE_PROFILE`, URLs, keys, `RELAY_KEYS`) | `PUBLIC_API_URL`, `LOGIN_TRUSTED_PROXY_HOPS`, `QEET_ID_RELAY_KEY` | `SERVER_URL`, `SESSION_SECRET`, `PUBLIC_API_URL`, `CONSOLE_TRUSTED_PROXY_HOPS`, `QEET_ID_RELAY_KEY` | `CONSOLE_URL`, `DOCS_URL` | none |
| Kit address (`<zone>`: TEST `test.id.qeet.in` over https, DEV/STAGING `<env>.id.qeet.localhost` over http) | `api.<zone>` | `login.<zone>` | `console.<zone>` | `<zone>` | `docs.<zone>` |

**No rebuild per environment.** Every browser-facing URL is read at runtime, so one digest serves
DEV, TEST and STAGING. The build-time values (`NEXT_PUBLIC_API_URL`, `VITE_API_URL`) remain the
fallback the Vercel deployments use. The website's pages are static, so its image is built with
`NEXT_PUBLIC_DASHBOARD_URL=/go/console` and `NEXT_PUBLIC_DOCS_URL=/go/docs`; `/go/...` redirects
to `CONSOLE_URL` / `DOCS_URL` at runtime. The docs link to nothing environment-specific.

The console's `__Host-` session cookie works over `http://*.localhost` in Chrome and Edge, which
treat `*.localhost` as a secure context.

## Not covered: `qeet-id-auth`

The Expo / React Native authenticator runs on a phone, which cannot reach `*.localhost` on the
tester's computer, and push notifications need a physical device. It is left out of the kit and
tested separately against a hosted environment. A build without `EXPO_PUBLIC_API_URL` talks to
**production**.

## Known gaps in the applications

| Repository | Gap | Effect in the kit |
|---|---|---|
| `qeet-id-server` | SAML (`internal/federation/saml/saml.go` ~387) and SCIM (`internal/federation/scim/scim.go` ~496) build public URLs as `https://` unless the host is `localhost` or `127.0.0.1`, ignoring `X-Forwarded-Proto` | SAML metadata and SCIM URLs are `https://` behind the `http` edge, so SAML and SCIM cannot be tested in DEV and STAGING (TEST is https, so they are right there) |
| `qeet-id-server` | Production rebuilds the server image instead of promoting the `production-approved` digest | Production runs the same source revision, not the same artifact UAT tested |
