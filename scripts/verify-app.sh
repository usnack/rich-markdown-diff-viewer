#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/create-demo.py
mkdir -p verification
rm -f verification/app-results.json verification/workflow-results.json
"$PWD/dist/Rich Markdown Diff.app/Contents/MacOS/RichMarkdownDiff" --repo "$PWD/verification/demo" --verify "$PWD/verification" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT
for ((i=0;i<75;i++)); do
  if [[ -f verification/workflow-results.json ]]; then break; fi
  sleep 1
done
node scripts/check-verification.mjs
