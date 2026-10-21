#!/usr/bin/env bash
# Smoke check of a RUNNING environment, through the local edge on 127.0.0.1
# (:80, and :443 for an https environment), as a browser reaches it:
#   - every address answers (API ready, health of login, console, website, docs,
#     the Mail inbox), and the OIDC issuer is this environment's
#   - https: the certificates chain to this computer's kit CA, and http://
#     redirects to https://
#   - an unknown address gets the edge's "Not a Qeet ID address" page
#   - no container of the environment publishes a host port (only the edge does)
# Names are pinned to 127.0.0.1 here, so it needs no DNS.
#
#   tests/smoke/check.sh [env]      default: test. Start the environment first.
set -uo pipefail

env=${1:-test}
kit=$(cd "$(dirname "$0")/../.." && pwd)
zone=$(sed -n 's/^QEET_KIT_ZONE=//p' "$kit/environments/$env.env")
scheme=$(sed -n 's/^QEET_KIT_SCHEME=//p' "$kit/environments/$env.env")
ca="${QEET_KIT_STATE_DIR:-$HOME/.qeet-id-test-kit}/edge/ca/root.crt"
fails=0

ok() { printf '  ok    %s\n' "$*"; }
bad() {
  printf '  FAIL  %s\n' "$*"
  fails=$((fails + 1))
}

# get HOST PATH [curl args...] — curl <scheme>://HOST/PATH via 127.0.0.1, an
# https one verified against this computer's kit CA only.
get() {
  local host=$1 path=$2
  shift 2
  if [ "$scheme" = https ]; then
    curl -sS --max-time 15 --cacert "$ca" --resolve "$host:443:127.0.0.1" "$@" "https://$host$path" 2> /dev/null
  else
    curl -sS --max-time 15 --resolve "$host:80:127.0.0.1" "$@" "http://$host$path" 2> /dev/null
  fi
}

expect() { # host path want
  local got
  got=$(get "$1" "$2" -o /dev/null -w '%{http_code}')
  if [ "$got" = "$3" ]; then ok "$scheme://$1$2 -> $got"; else bad "$scheme://$1$2 -> ${got:-no answer} (want $3)"; fi
}

echo "Smoke check: $(printf '%s' "$env" | tr '[:lower:]' '[:upper:]') at $scheme://console.$zone"

expect "api.$zone" /readyz 200
for svc in login console docs; do expect "$svc.$zone" /healthz 200; done
expect "$zone" /healthz 200
expect "mail.$zone" /livez 200
got=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --resolve "console.id.qeet.localhost:80:127.0.0.1" \
  "http://console.id.qeet.localhost/" 2> /dev/null)
if [ "$got" = 404 ]; then ok "unknown address -> 404"; else bad "unknown address -> ${got:-no answer} (want 404)"; fi

if [ "$scheme" = https ]; then
  got=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 --resolve "console.$zone:80:127.0.0.1" \
    "http://console.$zone/sign-in?x=1" 2> /dev/null)
  if [ "$got" = "308 https://console.$zone/sign-in?x=1" ]; then ok "http://console.$zone -> $got"; else bad "http://console.$zone -> ${got:-no answer} (want 308 to https)"; fi
fi

issuer=$(get "api.$zone" /.well-known/openid-configuration | sed -n 's/.*"issuer":"\([^"]*\)".*/\1/p')
if [ "$issuer" = "$scheme://api.$zone" ]; then ok "OIDC issuer $issuer"; else bad "OIDC issuer '${issuer:-none}' (want $scheme://api.$zone)"; fi

published=$(docker ps --filter "label=com.docker.compose.project=qeet-id-$env" --format '{{.Names}} {{.Ports}}' |
  grep -E -- '->' || true)
if [ -z "$published" ]; then ok "no host ports published by qeet-id-$env"; else bad "host ports published: $published"; fi

if [ $fails = 0 ]; then
  echo "smoke: all checks passed"
else
  echo "smoke: $fails check(s) failed"
  exit 1
fi
