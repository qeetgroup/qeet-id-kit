#!/usr/bin/env bash
# DELETE STAGING's data and secrets and start it fresh (asks first).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main reset staging "$@"
