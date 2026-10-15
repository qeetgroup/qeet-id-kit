#!/usr/bin/env bash
# Show STAGING: version, health and addresses.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main status staging "$@"
