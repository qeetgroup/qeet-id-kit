#!/usr/bin/env bash
# Start (or update) TEST, where QA tests the current release candidate.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main start test "$@"
