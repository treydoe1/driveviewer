#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
./build-app.sh

CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/driveviewer-clang-cache" swift build \
  -c release \
  --triple x86_64-apple-macosx14.0 \
  --disable-sandbox \
  --scratch-path .build-x86_64

app="dist/driveviewer.app"
lipo -create \
  .build/release/driveviewer \
  .build-x86_64/release/driveviewer \
  -output "$app/Contents/MacOS/driveviewer"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
archive="dist/driveviewer-v${version}-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
print "Packaged $PWD/$archive"
