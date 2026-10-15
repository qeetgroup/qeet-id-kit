#!/usr/bin/env bash
# Install a newer Qeet ID Kit next to this one.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main update-kit "$@"
