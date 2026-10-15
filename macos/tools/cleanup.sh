#!/usr/bin/env bash
# Remove old candidate images (keeps current and previous).
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main cleanup "$@"
