#!/usr/bin/env bash
# Update TEST to the newest release candidate. Data is kept.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main update test "$@"
