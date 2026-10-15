#!/usr/bin/env bash
# Go back to the previous STAGING candidate on this computer.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main rollback staging "$@"
