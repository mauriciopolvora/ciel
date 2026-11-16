#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"
if [[ "$SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
    printf 'A Developer ID Application identity is required.\n' >&2; exit 1
fi
sparkle_key="${SPARKLE_KEY_FILE:-$HOME/.config/secrets/ciel-sparkle.env}"
if [[ ! -r "$sparkle_key" ]]; then
    printf 'No update signing key at %s. Copy ciel-sparkle.env from mauriciovps with mode 600, or set SPARKLE_KEY_FILE.\n' "$sparkle_key" >&2; exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
export CIEL_ARCH="${CIEL_ARCH:-arm64}"
bash scripts/build.sh
app_path="$PWD/dist/Ciel.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive="$PWD/dist/Ciel-${version}-${CIEL_ARCH}.zip"
submission="$PWD/dist/Ciel-notary-submission.zip"
trap 'rm -f "$submission"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission"
xcrun notarytool submit "$submission" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --strict --deep "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
cp "$archive" dist/Ciel.zip
(cd dist && shasum -a 256 Ciel.zip > Ciel.zip.sha256)
bash scripts/appcast.sh "$app_path/Contents/Info.plist" "$archive" "$sparkle_key" "$PWD/dist/appcast.xml"
printf 'Review the signed app, then publish all five files under tag v%s with:\n\n' "$version"
printf '    gh release create %q' "v$version"
printf ' %q' "$archive" "$archive.sha256" "$PWD/dist/Ciel.zip" "$PWD/dist/Ciel.zip.sha256" "$PWD/dist/appcast.xml"
printf '\n'
