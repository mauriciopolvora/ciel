#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/dist/Ciel.app"
if pgrep -f "^${app_path}/Contents/MacOS/Ciel( |$)" >/dev/null; then
    printf 'Quit the dist copy of Ciel before rebuilding it.\n' >&2
    exit 1
fi
build_args=(-c release --product Ciel)
# Speech to text ships a Metal engine for Apple Silicon only.
case "${CIEL_ARCH:-native}" in
    native) ;;
    arm64) build_args+=(--arch arm64) ;;
    *) printf 'CIEL_ARCH must be native or arm64.\n' >&2; exit 1 ;;
esac
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p dist
staging_dir="$(mktemp -d "$PWD/dist/.ciel-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Ciel.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/Ciel" "$staged_app/Contents/MacOS/Ciel"
if [[ "$(lipo -archs "$staged_app/Contents/MacOS/Ciel")" != arm64 ]]; then
    printf 'Ciel builds for Apple Silicon only. Build on an Apple Silicon Mac or set CIEL_ARCH=arm64.\n' >&2
    exit 1
fi
framework="$staged_app/Contents/Frameworks/CTranscribe.framework"
mkdir -p "$staged_app/Contents/Frameworks"
ditto "$binary_dir/CTranscribe.framework" "$framework"
lipo "$framework/Versions/A/CTranscribe" -thin arm64 -output "$staging_dir/CTranscribe"
mv "$staging_dir/CTranscribe" "$framework/Versions/A/CTranscribe"
rm -rf "$framework/Headers" "$framework/Modules" "$framework/Versions/A/Headers" "$framework/Versions/A/Modules"
if ! otool -l "$staged_app/Contents/MacOS/Ciel" | grep -q 'path @executable_path/../Frameworks '; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$staged_app/Contents/MacOS/Ciel"
fi
cp Resources/ThirdPartyNotices.txt "$staged_app/Contents/Resources/ThirdPartyNotices.txt"
cp LICENSE "$staged_app/Contents/Resources/LICENSE.txt"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
if [[ ! -f .build/AppIcon.icns || scripts/GenerateIcon.swift -nt .build/AppIcon.icns || Resources/CloudPainting.png -nt .build/AppIcon.icns ]]; then
    swift scripts/GenerateIcon.swift Resources/CloudPainting.png .build
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
    printf 'Local ad-hoc signature. Public distribution requires Developer ID signing and notarization. Re-authorize window access after a local rebuild.\n' >&2
    sign=(codesign --force --sign -)
else
    sign=(codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
fi
# Nested code is signed before the bundle that seals it.
"${sign[@]}" "$framework"
"${sign[@]}" --entitlements Resources/Ciel.entitlements "$staged_app"
codesign --verify --strict --deep "$staged_app"
# Under the hardened runtime, library validation loads the framework only when it shares the app's Team ID, and ad-hoc code has none.
for code in "$staged_app" "$framework"; do
    details="$(codesign -dv "$code" 2>&1)"
    flags="$(sed -nE 's/.*flags=0x[0-9a-f]+\(([^)]*)\).*/,\1,/p' <<<"$details")"
    team="$(sed -n 's/^TeamIdentifier=//p' <<<"$details")"
    if [[ "$flags" == *,adhoc,* && "$flags" == *,runtime,* ]]; then
        printf '%s is ad-hoc signed with hardened runtime, so the app cannot load its framework.\n' "$code" >&2; exit 1
    elif [[ "$flags" != *,adhoc,* && "$flags" != *,runtime,* ]]; then
        printf '%s is Developer ID signed without hardened runtime, so it cannot be notarized.\n' "$code" >&2; exit 1
    elif [[ "$team" != "${app_team:=$team}" ]]; then
        printf 'The app and its framework have different Team IDs.\n' >&2; exit 1
    fi
done
if codesign -d --entitlements - "$staged_app" 2>/dev/null | grep -q disable-library-validation; then
    printf 'The app must keep library validation.\n' >&2; exit 1
fi
rm -rf "$app_path"
mv "$staged_app" "$app_path"
printf 'Built %s\n' "$app_path"
lipo -archs "$app_path/Contents/MacOS/Ciel"
lipo -archs "$app_path/Contents/Frameworks/CTranscribe.framework/CTranscribe"
du -sh "$app_path"
