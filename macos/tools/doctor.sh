#!/usr/bin/env bash
# Check this computer: Docker, memory, disk, port 80, sign-in.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main doctor "$@"
