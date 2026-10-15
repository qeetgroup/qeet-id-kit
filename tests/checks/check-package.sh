#!/usr/bin/env bash
# Verifies a built release ZIP before it is published:
#   - it extracts to qeet-id-kit/ and holds only the kit: nothing repository-only
#     (export-ignore), nothing sensitive or local (env files, keys, state, git)
#   - every file a tester needs is present, plus kit.lock
#   - Windows commands have CRLF line endings, shell scripts LF and +x
#   check-package.sh qeet-id-kit-v<version>.zip <version>
set -euo pipefail
zip=${1:?zip}
version=${2:?version}
root=qeet-id-kit

list=$(unzip -Z1 "$zip")
fail() { echo "::error::$*"; exit 1; }

# Repository-only paths (keep in step with export-ignore in .gitattributes).
# docs/ is repository-only except docs/troubleshooting.md, the testers' page.
repo_only="^$root/(release|tests|\.github)/|^$root/docs/.+|^$root/(AGENTS\.md|CLAUDE\.md|GEMINI\.md|qeet-repo\.yml|\.gitignore|\.gitattributes|\.dockerignore|\.editorconfig)$"
deny='(^|/)\.git/|(^|/)\.env$|(^|/)\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|(^|/)\.DS_Store$|(^|/)state/|(^|/)secrets/'
bad=$(grep -E "$repo_only|$deny" <<< "$list" | grep -vx "$root/docs/troubleshooting.md" || true)
[ -z "$bad" ] || fail "forbidden entries in $zip: $bad"
grep -vq "^$root/" <<< "$list" && fail "every entry must sit under $root/"

for f in VERSION kit.lock README.md CHANGELOG.md docs/troubleshooting.md \
  core/compose.yaml core/edge.compose.yaml core/image/Dockerfile core/image/keygen.sh \
  core/scripts/common.sh core/scripts/QeetIdKit.ps1 \
  environments/test.env environments/staging.env environments/optional.env \
  macos/test/start.sh macos/staging/start.sh macos/tools/login.sh \
  linux/test/start.sh linux/staging/start.sh linux/tools/login.sh \
  windows/test/start.cmd windows/staging/start.cmd windows/tools/login.cmd; do
  grep -qx "$root/$f" <<< "$list" || fail "missing $root/$f"
done

[ "$(unzip -p "$zip" "$root/VERSION" | tr -d '[:space:]')" = "$version" ] || fail "VERSION inside the ZIP is not $version"
unzip -p "$zip" "$root/kit.lock" | grep -qE "^QEET_KIT_IMAGE=[a-z0-9./-]+/qeet-id-test-kit:$version@sha256:[0-9a-f]{64}$" ||
  fail "kit.lock does not pin qeet-id-test-kit:$version by digest"

while IFS= read -r f; do
  case "$f" in
    *.cmd | *.bat | *.ps1 | *.psd1)
      unzip -p "$zip" "$f" | LC_ALL=C grep -q $'\r$' || fail "$f must have CRLF line endings" ;;
    *.sh | *.env | *.yaml)
      ! unzip -p "$zip" "$f" | LC_ALL=C grep -q $'\r' || fail "$f must have LF line endings" ;;
  esac
done <<< "$list"

# The settings testers edit in place ship without secret values.
"$(dirname "$0")/check-optional-env.sh" <(unzip -p "$zip" "$root/environments/optional.env") > /dev/null ||
  fail "environments/optional.env in the ZIP holds secret values"

# Shell commands must stay executable after extraction (macOS/Linux).
unzip -Z -l "$zip" | awk -v r="$root/" '$NF ~ "^"r"(macos|linux)/.*\\.sh$" && $1 !~ /x/ {print $NF; bad=1} END {exit bad}' ||
  fail "shell commands above are not executable in the ZIP"

echo "package ok: $zip ($(wc -l <<< "$list" | tr -d ' ') entries)"
