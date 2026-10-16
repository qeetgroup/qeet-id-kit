#!/usr/bin/env bash
# Stop DEV. Data is kept.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main stop dev "$@"
