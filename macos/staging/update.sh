#!/usr/bin/env bash
# Update STAGING to the candidate QA approved (the staging channel). Data is kept.
# shellcheck source=../../core/scripts/common.sh
. "$(dirname "$0")/../../core/scripts/common.sh"
kit_main update staging "$@"
