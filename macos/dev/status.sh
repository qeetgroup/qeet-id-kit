#!/usr/bin/env bash
# Show DEV: images, health and addresses.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main status dev "$@"
