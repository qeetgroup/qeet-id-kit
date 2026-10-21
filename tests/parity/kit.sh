#!/usr/bin/env bash
# Entry point for the parity test: runs any kit command through the macOS/Linux
# implementation, the way macos/ and linux/ commands do (run.sh calls it).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
# Ports 80 and 443 belong to this computer, not the fake docker: a real local
# edge must not fail the test.
port_busy() { return 1; }
# The fake CA is not a certificate, and a test never touches this computer's
# trust store (the Windows script trusts only on Windows).
ca_trusted() { return 0; }
kit_main "$@"
