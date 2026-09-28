#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

identity="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity.}"
profile="${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool Keychain profile.}"
app="dist/driveviewer.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="dist/driveviewer-v${version}-macos-universal.dmg"
result="dist/driveviewer-v${version}-dmg-notary-result.json"
stage="$(mktemp -d /private/tmp/driveviewer-dmg.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"

ditto "$app" "$stage/driveviewer.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -fs HFS+ -volname driveviewer -srcfolder "$stage" -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$identity" --identifier com.treykeys.driveviewer.dmg "$dmg"
codesign --verify --verbose=2 "$dmg"

xcrun notarytool submit "$dmg" \
  --keychain-profile "$profile" \
  --wait \
  --output-format json > "$result"

/usr/bin/python3 - "$result" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as result_file:
    result = json.load(result_file)
print(f"Notarization: {result.get('status', 'Unknown')}")
if result.get("status") != "Accepted":
    print(f"Submission ID: {result.get('id', 'unknown')}", file=sys.stderr)
    sys.exit(1)
PY

xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
print "Notarized $PWD/$dmg"
