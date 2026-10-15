#!/usr/bin/env bash
# Repository hygiene: no environment files, keys, kit state or release output may
# ever be tracked — and no tracked file may contain a private key. Run from the
# repository root (CI: validate.yml).
set -euo pipefail

deny='(^|/)\.env$|(^|/)\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|\.jks$|(^|/)id_(rsa|ed25519|ecdsa)|(^|/)credentials(\.|$)|(^|/)kit\.lock$|\.zip$|\.tfstate($|\.)|\.tfvars$'
allow='(^|/)\.example\.env$'

# Tracked plus not-yet-committed files (respecting .gitignore), so a local run
# previews exactly what a commit would add.
files=$(git ls-files --cached --others --exclude-standard)
bad=$(grep -E "$deny" <<< "$files" | grep -Ev "$allow" || true)
if [ -n "$bad" ]; then
  echo "::error::sensitive or local-only files are tracked:"
  awk '{print "  " $0}' <<< "$bad"
  exit 1
fi

# Content scan (names only are printed, never the matching text).
keys=$(git grep --untracked -lIE -e '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' -- . || true)
if [ -n "$keys" ]; then
  echo "::error::tracked files contain a private key block:"
  awk '{print "  " $0}' <<< "$keys"
  exit 1
fi
echo "tracked files: no env files, keys, kit state or release output ($(wc -l <<< "$files" | tr -d ' ') files checked)"
