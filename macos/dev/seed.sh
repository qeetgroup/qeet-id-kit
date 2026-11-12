#!/usr/bin/env bash
# REPLACE DEV's data with the server's demo data (asks first).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main seed dev "$@"
