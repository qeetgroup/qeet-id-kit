#!/usr/bin/env bash
# Stop TEST. Data is kept.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main stop test "$@"
