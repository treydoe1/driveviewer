#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/driveviewer-clang-cache" swift build -c release --disable-sandbox --scratch-path .build

app="dist/driveviewer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/driveviewer "$app/Contents/MacOS/driveviewer"
cp Info.plist "$app/Contents/Info.plist"
cp Assets/driveviewer.icns "$app/Contents/Resources/driveviewer.icns"
codesign --force --sign - "$app"
print "Built $PWD/$app"
