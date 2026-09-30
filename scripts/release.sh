#!/bin/bash
# Create a notarized archive. Credentials stay in the macOS keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"
if [[ "$SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
    printf 'A Developer ID Application identity is required.\n' >&2; exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
export CIEL_ARCH="${CIEL_ARCH:-universal}"
bash scripts/build.sh
app_path="$PWD/dist/Ciel.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive="$PWD/dist/Ciel-${version}-${CIEL_ARCH}.zip"
submission="$PWD/dist/Ciel-notary-submission.zip"
trap 'rm -f "$submission"' EXIT
# The build uses hardened runtime and a secure timestamp.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission"
xcrun notarytool submit "$submission" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --strict "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
# Archive again after stapling, then hash the exact distributable.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
printf 'Release archive: %s\n' "$archive"
