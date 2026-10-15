#!/usr/bin/env bash
# Entry point for the parity test: runs any kit command through the macOS/Linux
# implementation, the way macos/ and linux/ commands do (run.sh calls it).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main "$@"
