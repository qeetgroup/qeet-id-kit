#!/usr/bin/env bash
# Start DEV: --build builds your working trees; --image <component>=<ref> picks an image;
# with neither, DEV runs the images it ran last time.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main start dev "$@"
