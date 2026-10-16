#!/usr/bin/env bash
# Parity test: the macOS/Linux (core/scripts/common.sh) and Windows
# (core/scripts/QeetIdKit.ps1) implementations must issue the same docker commands
# for the same scenario. Runs both against the fake docker in this directory and
# diffs the normalised transcripts.
#
#   run.sh BASH PWSH     e.g. run.sh bash pwsh   (CI runs BASH as bash 3.2)
set -euo pipefail

BASH_BIN=${1:-bash}
PWSH_BIN=${2:-pwsh}
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A digest-pinned release, as the registry would serve it.
"$KIT/release/release-manifest.sh" to-env "$KIT/release/example.manifest.json" > "$WORK/release.env"

# DEV runs chosen images here (--build needs the source checkouts): the
# release's own images, one --image per component.
dev_images=""
for c in server login console website docs; do
  dev_images="$dev_images --image $c=$(sed -n "s/^QEET_ID_$(tr '[:lower:]' '[:upper:]' <<< "$c")_IMAGE=//p" "$WORK/release.env")"
done

# One step per kit command, with TEST, STAGING and DEV side by side: stopping
# one keeps the edge for the others; Reset touches only its own environment;
# DEV restarts from the images it ran last time.
SCENARIO=(
  "start test --no-browser"
  "start staging --no-browser"
  "start dev --no-browser$dev_images"
  "stop test"
  "reset staging --yes --no-browser"
  "stop dev"
  "start dev --no-browser"
  "reset dev --yes --no-browser"
  "start test --no-browser"
  "stop staging"
  "stop all"
)

run() { # name command-prefix...
  local name=$1 step
  shift
  local state="$WORK/$name-state" kitstate="$WORK/$name-kit"
  mkdir -p "$state" "$kitstate"
  for step in "${SCENARIO[@]}"; do
    echo "## $step" >> "$WORK/$name.log"
    # shellcheck disable=SC2086 # the scenario step is a word list
    PATH="$HERE:$PATH" FAKE_DOCKER_LOG="$WORK/$name.log" FAKE_DOCKER_STATE="$state" \
      FAKE_RELEASE_ENV="$WORK/release.env" QEET_KIT_STATE_DIR="$kitstate" \
      QEET_KIT_REGISTRY=ghcr.io/qeetgroup "$@" $step > "$WORK/$name.out" 2>&1 ||
      { echo "::error::$name failed at '$step'"; cat "$WORK/$name.out"; exit 1; }
  done
  sed -e "s#$kitstate#<STATE>#g" -e "s#$KIT#<KIT>#g" -e 's#DATE=[^ ]*#DATE=<DATE>#g' \
    "$WORK/$name.log" > "$WORK/$name.norm"
}

run bash "$BASH_BIN" "$HERE/kit.sh"
run pwsh "$PWSH_BIN" -NoLogo -NoProfile -File "$KIT/core/scripts/QeetIdKit.ps1"

if diff -u "$WORK/bash.norm" "$WORK/pwsh.norm"; then
  echo "parity: $(grep -vc '^##' "$WORK/bash.norm") docker invocations identical across ${#SCENARIO[@]} steps"
else
  echo "::error::bash and PowerShell issue different docker commands (diff above)"
  exit 1
fi
