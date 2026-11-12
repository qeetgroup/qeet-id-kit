# Application image contract

**Applies to:** `qeet-id-server`, `qeet-id-hosted` (the hosted login, image `qeet-id-login`) and
`qeet-id-console`. **Consumed by:** `publish-candidate` and the kit.

Every application that runs in DEV, TEST or STAGING provides a container image meeting this
contract. Production deploys separately (server: the same image, copied to ECR by `deploy.yml`;
login and console: Vercel).

## Publishing

| Requirement | Detail |
|---|---|
| Registry / name | `ghcr.io/qeetgroup/<image>`: `qeet-id-server`, `qeet-id-login` (built by `qeet-id-hosted`), `qeet-id-console` |
| Tag | `sha-<full 40-hex commit>` only, **immutable**; a re-run never moves it. No `rc.N`, no `latest`. |
| When | `candidate.yml`: every push to `release/YEAR.MONTH.0` or `hotfix/YEAR.MONTH.N` |
| Platforms | `linux/amd64` and `linux/arm64` (one index) |
| Labels (config and index annotation) | `org.opencontainers.image.source` = `https://github.com/qeetgroup/<repository>` · `org.opencontainers.image.revision` = commit · `org.opencontainers.image.version` = `YEAR.MONTH.N` · `org.opencontainers.image.created` · `in.qeet.release` = `YEAR.MONTH.N` · `in.qeet.source-branch` = `release/YEAR.MONTH.0` or `hotfix/YEAR.MONTH.N` · server only: `in.qeet.id.schema-version` = highest migration number |
| Workflow security | Actions pinned by commit SHA; job permissions `contents: read`, `packages: write` only |
| Package access | **Manage Actions access → `qeet-id-kit`: Read**, so `publish-candidate` can inspect it |

## Runtime

| | Server | Login | Console |
|---|---|---|---|
| Port | 4001 | 3000 | 3000 |
| User | non-root (distroless `nonroot`) | non-root (`node`) | non-root (`node`) |
| Health | `/qeet-id-server healthcheck` (→ `/readyz` = 200) | `GET /healthz` = 200 JSON `{status, service, version, revision}` | same as login |
| Runtime configuration | env (`SERVICE_ENV=local`, `SERVICE_PROFILE`, URLs, keys, `RELAY_KEYS`) | `PUBLIC_API_URL`, `LOGIN_TRUSTED_PROXY_HOPS`, `QEET_ID_RELAY_KEY` | `SERVER_URL`, `SESSION_SECRET`, `PUBLIC_API_URL`, `CONSOLE_TRUSTED_PROXY_HOPS`, `QEET_ID_RELAY_KEY` |
| Kit address (`<zone>` = `<env>.id.qeet.in`, over https) | `api.<zone>` | `login.<zone>` | `console.<zone>` |

The bare `<zone>` is the edge's own: it serves `/.well-known/assetlinks.json` (so Qeet ID on
Android may use the environment's passkeys) and sends anything else to the console.

**No rebuild per environment.** Every browser-facing URL is read at runtime, so one digest serves
DEV, TEST and STAGING. The build-time values (`NEXT_PUBLIC_API_URL`, `VITE_API_URL`) remain the
fallback the Vercel deployments use.

The console's `__Host-` session cookie needs a secure context: every kit address is `https`.
The console and login reach the API by the same https address as the browser and trust the
edge's certificates through `NODE_EXTRA_CA_CERTS` (this computer's kit CA).

## Not covered: `qeet-id-auth`

The Expo / React Native authenticator runs on a phone, which cannot reach the kit: the kit's
names resolve to `127.0.0.1`, the phone itself, and the phone does not trust the computer's kit
CA. Push notifications also need a physical device. It is left out of the kit and
tested separately against a hosted environment. A build without `EXPO_PUBLIC_API_URL` talks to
**production**.

## Known gaps in the applications

| Repository | Gap | Effect in the kit |
|---|---|---|
| `qeet-id-server` | SAML (`internal/federation/saml/saml.go` ~387) and SCIM (`internal/federation/scim/scim.go` ~496) build public URLs as `https://` unless the host is `localhost` or `127.0.0.1`, ignoring `X-Forwarded-Proto` | None since kit 1.4.0: every environment is `https`, so those URLs are right (before, `http` environments got `https://` URLs) |
