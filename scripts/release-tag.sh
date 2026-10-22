#!/bin/bash
set -euo pipefail
# Use committer time, not author time or the workflow execution time.
RMD_COMMIT_DATE=$(TZ=Asia/Seoul git show -s --format=%cd --date=format-local:%y%m%d HEAD)
RMD_COMMIT_HASH=$(git rev-parse --short=7 HEAD)
printf '%s-%s\n' "$RMD_COMMIT_DATE" "$RMD_COMMIT_HASH"
