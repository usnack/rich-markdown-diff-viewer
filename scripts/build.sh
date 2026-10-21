#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Rich Markdown Diff.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build
npx esbuild web/src/app.js --bundle --format=iife --target=safari17 --outfile="$APP/Contents/Resources/app.js" --log-level=warning
node scripts/notices.mjs
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp web/index.html web/style.css "$APP/Contents/Resources/"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -O -module-cache-path "$PWD/.build/modules" native/Git.swift native/Comments.swift native/CommentsBridge.swift native/Verification.swift native/main.swift -o "$APP/Contents/MacOS/RichMarkdownDiff" -framework AppKit -framework WebKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>RichMarkdownDiff</string><key>CFBundleIdentifier</key><string>local.richmarkdowndiff.app</string><key>CFBundleName</key><string>Rich Markdown Diff</string><key>CFBundleVersion</key><string>2</string><key>CFBundleShortVersionString</key><string>1.1.0</string><key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Markdown Document</string><key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string><string>mdown</string></array><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string></dict></array><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "$APP"
