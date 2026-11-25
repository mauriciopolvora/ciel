#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/dist/Ciel.app"
if pgrep -f "^${app_path}/Contents/MacOS/Ciel( |$)" >/dev/null; then
    printf 'Quit the dist copy of Ciel before rebuilding it.\n' >&2
    exit 1
fi
build_args=(-c release --product Ciel)
# WARNING: the transcribe.cpp Metal engine builds for Apple Silicon only.
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
sparkle="$staged_app/Contents/Frameworks/Sparkle.framework"
ditto "$binary_dir/Sparkle.framework" "$sparkle"
# WARNING: Sparkle uses its XPC services only in sandboxed apps, and its sandboxing guide allows removing them.
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
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
# WARNING: codesign must sign nested code before the bundle that seals it.
"${sign[@]}" "$framework"
"${sign[@]}" "$sparkle/Versions/B/Autoupdate"
"${sign[@]}" "$sparkle/Versions/B/Updater.app"
"${sign[@]}" "$sparkle"
"${sign[@]}" --entitlements Resources/Ciel.entitlements "$staged_app"
codesign --verify --strict --deep "$staged_app"
# WARNING: library validation loads a framework only when it shares the app's Team ID, and ad-hoc code has none.
for code in "$staged_app" "$framework" "$sparkle" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app"; do
    details="$(codesign -dv "$code" 2>&1)"
    flags="$(sed -nE 's/.*flags=0x[0-9a-f]+\(([^)]*)\).*/,\1,/p' <<<"$details")"
    team="$(sed -n 's/^TeamIdentifier=//p' <<<"$details")"
    if [[ "$flags" == *,adhoc,* && "$flags" == *,runtime,* ]]; then
        printf '%s is ad-hoc signed with hardened runtime, so the app cannot load its frameworks.\n' "$code" >&2; exit 1
    elif [[ "$flags" != *,adhoc,* && "$flags" != *,runtime,* ]]; then
        printf '%s is Developer ID signed without hardened runtime, so it cannot be notarized.\n' "$code" >&2; exit 1
    elif [[ "$team" != "${app_team:=$team}" ]]; then
        printf '%s and the app have different Team IDs.\n' "$code" >&2; exit 1
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
lipo -archs "$app_path/Contents/Frameworks/Sparkle.framework/Sparkle"
du -sh "$app_path"
