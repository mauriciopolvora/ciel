#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/dist/Ciel.app"
if pgrep -f "^${app_path}/Contents/MacOS/Ciel( |$)" >/dev/null; then
    printf 'Quit the dist copy of Ciel before rebuilding it.\n' >&2
    exit 1
fi
build_args=(-c release --product Ciel)
case "${CIEL_ARCH:-native}" in
    native) ;;
    arm64|x86_64) build_args+=(--arch "$CIEL_ARCH") ;;
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
    *) printf 'CIEL_ARCH must be native, arm64, x86_64, or universal.\n' >&2; exit 1 ;;
esac
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p dist
staging_dir="$(mktemp -d "$PWD/dist/.ciel-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Ciel.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/Ciel" "$staged_app/Contents/MacOS/Ciel"
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
    codesign --force --sign - --options runtime "$staged_app"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$staged_app"
fi
codesign --verify --strict "$staged_app"
# Replace only the generated bundle after the staged build and signature pass.
rm -rf "$app_path"
mv "$staged_app" "$app_path"
printf 'Built %s\n' "$app_path"
lipo -archs "$app_path/Contents/MacOS/Ciel"
du -sh "$app_path"
