#!/usr/bin/env bash
# Sign in to GitHub Packages once, to download Qeet ID.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main login "$@"
