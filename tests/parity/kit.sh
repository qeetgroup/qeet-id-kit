#!/usr/bin/env bash
# Entry point for the parity test: runs any kit command through the macOS/Linux
# implementation, the way macos/ and linux/ commands do (run.sh calls it).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
# Port 80 belongs to this computer, not the fake docker: a real local edge must
# not fail the test.
port80_busy() { return 1; }
kit_main "$@"
