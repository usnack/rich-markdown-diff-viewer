#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Rich Markdown Diff.app"
if [[ ! -d "$APP" ]]; then
  echo '앱을 먼저 빌드하세요: npm run build' >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo '소스와 앱의 버전을 맞추기 위해 변경을 커밋한 뒤 패키징하세요.' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Rich Markdown Diff.app.zip"
git archive --format=zip --prefix=rich-markdown-diff-viewer/ --output="$PWD/dist/rich-markdown-diff-source.zip" HEAD
(cd dist && shasum -a 256 'Rich Markdown Diff.app.zip' rich-markdown-diff-source.zip > SHA256SUMS)
unzip -tq 'dist/Rich Markdown Diff.app.zip'
unzip -tq dist/rich-markdown-diff-source.zip
echo "패키지: $PWD/dist"
