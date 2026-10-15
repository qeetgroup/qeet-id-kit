#!/usr/bin/env bash
# Testers edit environments/optional.env in place, so the committed (and shipped)
# file must not hold real secrets: every secret-named key (*_SECRET,
# *_SECRET_KEY, *_TOKEN, *_PRIVATE_KEY, *_API_KEY, *_PASSWORD) must be empty.
#   check-optional-env.sh [file]      default: environments/optional.env
set -euo pipefail
file=${1:-$(cd "$(dirname "$0")/../.." && pwd)/environments/optional.env}

# Name the keys only: the values may be real secrets.
keys=$(sed -nE 's/^([A-Z0-9_]*(_SECRET|_SECRET_KEY|_TOKEN|_PRIVATE_KEY|_API_KEY|_PASSWORD))=(.+)$/\1/p' "$file" |
  tr '\n' ' ')
if [ -n "$keys" ]; then
  echo "::error::environments/optional.env must not hold secrets; these keys have values: $keys"
  echo "Never commit your own values: empty them before committing."
  exit 1
fi
echo "optional.env: no secret values ($(grep -cE '^[A-Z0-9_]*(_SECRET|_SECRET_KEY|_TOKEN|_PRIVATE_KEY|_API_KEY|_PASSWORD)=' "$file") secret keys, all empty)"
