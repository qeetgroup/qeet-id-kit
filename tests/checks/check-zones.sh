#!/usr/bin/env bash
# The edge (core/edge.compose.yaml) routes each environment by the zone and
# scheme its environments/<env>.env defines. They are written in both places;
# this keeps them in step:
#   - every environment file defines QEET_KIT_ZONE and QEET_KIT_SCHEME
#   - the edge imports that environment with the same scheme and zone, an https
#     one also with its http->https redirect, and answers to its names on the
#     environment's edge network
#   - an https zone is one the kit CA may vouch for (core/image/ca.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "::error::$*"; exit 1; }

edge=core/edge.compose.yaml
for f in environments/dev.env environments/test.env environments/staging.env; do
  [ -f "$f" ] || continue
  env=$(basename "$f" .env)
  zone=$(sed -n 's/^QEET_KIT_ZONE=//p' "$f")
  scheme=$(sed -n 's/^QEET_KIT_SCHEME=//p' "$f")
  [ -n "$zone" ] || fail "$f does not define QEET_KIT_ZONE"
  case "$scheme" in http | https) ;; *) fail "$f: QEET_KIT_SCHEME must be http or https (got '$scheme')" ;; esac
  label=$(tr '[:lower:]' '[:upper:]' <<< "$env")
  grep -Eq "^[[:space:]]+import environment $env $label [A-Za-z]+ $scheme $zone\$" "$edge" ||
    fail "$edge does not import $env with '$scheme $zone' (environments/$env.env)"
  grep -Eq "^[[:space:]]+aliases: \[.*api\.$zone" "$edge" ||
    fail "$edge: the edge does not answer to api.$zone on the $env network"
  if [ "$scheme" = https ]; then
    grep -Eq "^[[:space:]]+import to-https $zone\$" "$edge" || fail "$edge does not redirect http://*.$zone to https"
    grep -q "permitted;DNS:$zone" core/image/ca.sh || fail "core/image/ca.sh does not let the kit CA vouch for $zone"
  else
    case "$zone" in *.localhost) ;; *) fail "$f: plain http needs a *.localhost zone (got $zone)" ;; esac
  fi
done
echo "zones ok"
