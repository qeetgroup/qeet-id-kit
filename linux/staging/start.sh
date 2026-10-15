#!/usr/bin/env bash
# Start (or update) STAGING, where Product/UAT validates the candidate QA approved.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main start staging "$@"
