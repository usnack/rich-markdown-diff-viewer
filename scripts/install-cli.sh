#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
DEST=${1:-/usr/local/bin}
mkdir -p "$DEST"
if [ -e "$DEST/rmdiff" ] || [ -L "$DEST/rmdiff" ]; then
  if [ "$(readlink "$DEST/rmdiff" 2>/dev/null || true)" = "$ROOT/scripts/rmdiff" ]; then printf '이미 설치됨: %s/rmdiff\n' "$DEST"; exit 0; fi
  printf '기존 명령을 덮어쓰지 않았습니다: %s/rmdiff\n' "$DEST" >&2; exit 1
fi
ln -s "$ROOT/scripts/rmdiff" "$DEST/rmdiff"
printf '설치됨: %s/rmdiff\n' "$DEST"
