#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# notarytool takes the Apple ID password as an argument, so this script never traces.
{ set +x; } 2>/dev/null
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate.}"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    notary=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
else
    printf 'Set NOTARY_PROFILE to a notarytool keychain profile, or set NOTARY_APPLE_ID, NOTARY_PASSWORD and NOTARY_TEAM_ID.\n' >&2; exit 1
fi
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
notary_result="$PWD/dist/notary-result.json"
trap 'rm -f "$submission" "$notary_result"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission"
xcrun notarytool submit "$submission" "${notary[@]}" --wait --output-format json >"$notary_result" || true
notary_status=$(plutil -extract status raw "$notary_result" 2>/dev/null || printf 'missing')
if [[ "$notary_status" != Accepted ]]; then
    printf 'Notarization status: %s\n' "$notary_status" >&2
    if notary_id=$(plutil -extract id raw "$notary_result" 2>/dev/null); then
        xcrun notarytool log "$notary_id" "${notary[@]}" >&2 || true
    fi
    exit 1
fi
printf 'Notarization accepted.\n'
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
