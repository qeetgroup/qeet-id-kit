#!/bin/sh
# Generates one environment's TEST-ONLY secrets into the given directory:
#   postgres.env  POSTGRES_PASSWORD
#   server.env    DB_URL, JWT_SECRET, SECRETS_KEY, JWT_SIGNING_KEY, SAML_IDP_KEY, SAML_IDP_CERT
#   console.env   SESSION_SECRET
#   relay.env     RELAY_KEYS (server) and QEET_ID_RELAY_KEY (console, login): the
#                 same key, so the server trusts the visitor address they relay
# Values are random per environment and per machine; they protect nothing outside
# this local runtime and are never reused anywhere else. Refuses to overwrite
# existing data secrets: Qeet ID encrypts data with them, so re-keying an existing
# database would make it unreadable (Reset deletes them together with the data).
# relay.env encrypts nothing, so an environment created before it existed gets
# one on its own and keeps its data secrets.
set -eu

out=${1:-/out}
env=${QEET_KIT_ENV:-}
case "$env" in
  dev|test|staging) ;;
  *) echo "keygen: QEET_KIT_ENV must be dev, test or staging" >&2; exit 2 ;;
esac
present=0
for f in postgres.env server.env console.env; do
  [ ! -e "$out/$f" ] || present=$((present + 1))
done
if [ "$present" != 0 ] && { [ "$present" != 3 ] || [ -e "$out/relay.env" ]; }; then
  echo "keygen: secrets already exist in $out; refusing to re-key existing data" >&2
  exit 3
fi

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# place FILE...: moves each generated file into place, owner-only.
place() {
  for f in "$@"; do
    cp "$work/$f" "$out/$f.tmp"
    chmod 600 "$out/$f.tmp"
    mv "$out/$f.tmp" "$out/$f"
  done
}

relay_key=$(openssl rand -hex 32)
{
  printf 'RELAY_KEYS=%s\n' "$relay_key"
  printf 'QEET_ID_RELAY_KEY=%s\n' "$relay_key"
} > "$work/relay.env"
if [ "$present" = 3 ]; then
  place relay.env
  echo "keygen: added the relay key for $env"
  exit 0
fi

# ES256 signing key as PKCS#8 — a single PEM block, as the server requires.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/jwt.pem" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -subj "/CN=Qeet ID ${env} SAML IdP (test only)" \
  -keyout "$work/saml.key" -out "$work/saml.crt" 2>/dev/null

# Hex keeps generated values free of characters the env-file parser or a URL
# would interpret.
pg_password=$(openssl rand -hex 24)

printf 'POSTGRES_PASSWORD=%s\n' "$pg_password" > "$work/postgres.env"
{
  printf 'DB_URL=postgres://qeet_id:%s@postgres:5432/qeet_id_%s?sslmode=disable\n' "$pg_password" "$env"
  printf 'JWT_SECRET=%s\n' "$(openssl rand -hex 32)"
  printf 'SECRETS_KEY=%s\n' "$(openssl rand -base64 32)"
  printf 'JWT_SIGNING_KEY="%s"\n' "$(cat "$work/jwt.pem")"
  printf 'SAML_IDP_KEY="%s"\n' "$(cat "$work/saml.key")"
  printf 'SAML_IDP_CERT="%s"\n' "$(cat "$work/saml.crt")"
} > "$work/server.env"
printf 'SESSION_SECRET=%s\n' "$(openssl rand -hex 32)" > "$work/console.env"

place postgres.env server.env console.env relay.env
echo "keygen: generated test-only secrets for $env"
