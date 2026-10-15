#!/usr/bin/env bash
# Smoke check of a RUNNING environment, through the local edge on 127.0.0.1:80,
# as a browser reaches it:
#   - every address answers (API ready, health of login, console, website, docs,
#     the Mail inbox), and the OIDC issuer is this environment's
#   - an unknown address gets the edge's "Not a Qeet ID address" page
#   - no container of the environment publishes a host port (only the edge does)
#
#   tests/smoke/check.sh [env]      default: test. Start the environment first.
set -uo pipefail

env=${1:-test}
zone="$env.id.qeet.localhost"
fails=0

ok() { printf '  ok    %s\n' "$*"; }
bad() {
  printf '  FAIL  %s\n' "$*"
  fails=$((fails + 1))
}

# status HOST PATH — the HTTP status of http://HOST/PATH via 127.0.0.1:80.
status() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$1:80:127.0.0.1" "http://$1$2" 2> /dev/null
}

expect() { # host path want
  local got
  got=$(status "$1" "$2")
  if [ "$got" = "$3" ]; then ok "http://$1$2 -> $got"; else bad "http://$1$2 -> ${got:-no answer} (want $3)"; fi
}

echo "Smoke check: $(printf '%s' "$env" | tr '[:lower:]' '[:upper:]') at http://console.$zone"

expect "api.$zone" /readyz 200
for svc in login console docs; do expect "$svc.$zone" /healthz 200; done
expect "$zone" /healthz 200
expect "mail.$zone" /livez 200
expect console.id.qeet.localhost / 404

issuer=$(curl -sS --max-time 15 --resolve "api.$zone:80:127.0.0.1" \
  "http://api.$zone/.well-known/openid-configuration" 2> /dev/null |
  sed -n 's/.*"issuer":"\([^"]*\)".*/\1/p')
if [ "$issuer" = "http://api.$zone" ]; then ok "OIDC issuer $issuer"; else bad "OIDC issuer '${issuer:-none}' (want http://api.$zone)"; fi

published=$(docker ps --filter "label=com.docker.compose.project=qeet-id-$env" --format '{{.Names}} {{.Ports}}' |
  grep -E -- '->' || true)
if [ -z "$published" ]; then ok "no host ports published by qeet-id-$env"; else bad "host ports published: $published"; fi

if [ $fails = 0 ]; then
  echo "smoke: all checks passed"
else
  echo "smoke: $fails check(s) failed"
  exit 1
fi
