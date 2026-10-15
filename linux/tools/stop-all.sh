#!/usr/bin/env bash
# Stop every environment and the local edge. Data is kept.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main stop all "$@"
