#!/usr/bin/env bash
# Show TEST logs: [server|login|console|website|docs|db|mail|edge] [--follow] [--tail N].
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main logs --env test "$@"
