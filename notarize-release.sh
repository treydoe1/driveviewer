#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

identity="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity.}"
profile="${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool Keychain profile.}"
app="dist/driveviewer.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
submission="dist/driveviewer-v${version}-notary-submission.zip"
result="dist/driveviewer-v${version}-notary-result.json"
archive="dist/driveviewer-v${version}-macos-universal.zip"

test -d "$app"
architectures="$(lipo -archs "$app/Contents/MacOS/driveviewer")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
  print -u2 "Build the universal app with ./package-release.sh first."
  exit 1
}

codesign --force --timestamp --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"

xcrun notarytool submit "$submission" \
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

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
unzip -tq "$archive"
print "Notarized $PWD/$archive"
