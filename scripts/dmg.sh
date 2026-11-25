#!/bin/bash
set -euo pipefail
# WARNING: with CDPATH set, cd prints the directory and corrupts the paths read from it.
unset CDPATH
# WARNING: sort order and number formats follow the locale.
export LC_ALL=C
fail() { printf '%s\n' "$1" >&2; exit 1; }
usage='Usage: bash scripts/dmg.sh path/to/Ciel.app output.dmg, or bash scripts/dmg.sh --layout'
case $# in
    1) [[ "$1" == --layout ]] || fail "$usage" ;;
    2)
        [[ -d "$1" && "$(basename "$1")" == Ciel.app ]] || fail "$1 is not a Ciel.app bundle."
        app="$(cd "$1" && pwd)"
        if [[ "$2" == /* ]]; then output="$2"; else output="$PWD/$2"; fi
        ;;
    *) fail "$usage" ;;
esac
cd "$(dirname "$0")/.."
width=640
height=380
icon_size=128
text_size=13
icon_y=172
app_x=172
applications_x=468
# WARNING: Finder stores window bounds with the title bar, which is 28 points tall.
window_height=$((height + 28))
layout=Resources/DiskImage.DS_Store

mkdir -p .build
work="$(mktemp -d "$PWD/.build/ciel-dmg.XXXXXX")"
mountpoint="$work/mount"
attached=false
cleanup() {
    if [[ "$attached" == true ]]; then
        hdiutil detach "$mountpoint" -quiet || hdiutil detach "$mountpoint" -force -quiet || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT
attach() {
    mkdir "$mountpoint"
    hdiutil attach "$1" -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" -quiet
    attached=true
}
detach() {
    hdiutil detach "$mountpoint" -quiet
    attached=false
}

swift scripts/GenerateDMGBackground.swift Resources/CloudPainting.png "$work" \
    "$width" "$height" "$icon_size" "$icon_y" "$app_x" "$applications_x"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" 2>/dev/null

if [[ $# -eq 1 ]]; then
    command -v python3 >/dev/null || fail 'dmgbuild needs python3 3.11 or later, and there is no python3.'
    python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' ||
        fail "dmgbuild needs python3 3.11 or later, and python3 is $(python3 --version 2>&1)."
    venv=.build/dmg-venv
    requirements=scripts/dmg-requirements.txt
    stamp="$({ python3 --version; cat "$requirements"; } | shasum -a 256)"
    if [[ "$(cat "$venv/requirements.sha256" 2>/dev/null)" != "$stamp" || ! -x "$venv/bin/dmgbuild" ]]; then
        rm -rf "$venv"
        python3 -m venv "$venv"
        "$venv/bin/python" -m pip install --quiet --disable-pip-version-check \
            --require-hashes --only-binary :all: -r "$requirements"
        printf '%s\n' "$stamp" >"$venv/requirements.sha256"
    fi
    # WARNING: Finder finds each icon by its file name, so an empty folder stands in for the app.
    mkdir "$work/Ciel.app"
    "$venv/bin/dmgbuild" -s scripts/dmg-settings.py \
        -D app="$work/Ciel.app" -D background="$work/background.tiff" \
        -D width="$width" -D window_height="$window_height" -D icon_size="$icon_size" -D text_size="$text_size" \
        -D icon_y="$icon_y" -D app_x="$app_x" -D applications_x="$applications_x" \
        Ciel "$work/layout.dmg" >/dev/null
    attach "$work/layout.dmg"
    cp "$mountpoint/.DS_Store" "$layout"
    detach
    printf 'Wrote %s. Build an image, open it in Finder and look at the window before you commit it.\n' "$layout"
    exit 0
fi

[[ -f "$layout" ]] || fail "There is no $layout. Run bash scripts/dmg.sh --layout."
hex() { xxd -p | tr -d '\n'; }
# WARNING: a .DS_Store icon position record is the UTF-16 name, Iloc, blob, the length 16, x and y.
layout_hex="$(hex <"$layout")"
placed() {
    local name_hex
    name_hex="$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-16BE | hex)"
    [[ "$layout_hex" == *"${name_hex}496c6f63626c6f6200000010$(printf '%08x%08x' "$2" "$icon_y")"* ]]
}
# WARNING: .DS_Store icon view settings are icvp, blob, a 4-byte length, then a binary property list.
settings_at="$(grep -abo icvpblob "$layout" | cut -d: -f1 || true)"
[[ "$settings_at" =~ ^[0-9]+$ ]] ||
    fail "$layout does not hold one set of icon view settings. Run bash scripts/dmg.sh --layout."
tail -c "+$((settings_at + 13))" "$layout" | head -c "$((16#$(xxd -s "$((settings_at + 8))" -l 4 -p "$layout")))" >"$work/icvp.plist"
setting() { plutil -extract "$1" raw "$work/icvp.plist"; }
# WARNING: a .DS_Store background reference is a length, the path, and a zero byte of padding.
background_path='Ciel:.background.tiff'
background_hex="$(printf '%04x' "${#background_path}")$(printf '%s' "$background_path" | hex)00"
if ! placed Ciel.app "$app_x" || ! placed Applications "$applications_x" ||
    ! grep -aqF "{$width, $window_height}" "$layout" ||
    [[ "$(setting iconSize)" != "$(printf '%.6f' "$icon_size")" || "$(setting textSize)" != "$(printf '%.6f' "$text_size")" ]] ||
    [[ "$(setting backgroundType)" != 2 || "$(setting backgroundImageAlias | base64 -D | hex)" != *"$background_hex"* ]]; then
    fail "$layout does not match the geometry in scripts/dmg.sh. Run bash scripts/dmg.sh --layout."
fi

stage="$work/stage"
mkdir "$stage"
ditto "$app" "$stage/Ciel.app"
ln -s /Applications "$stage/Applications"
cp "$work/background.tiff" "$stage/.background.tiff"
cp "$layout" "$stage/.DS_Store"
hdiutil create -srcfolder "$stage" -volname Ciel -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$work/Ciel.dmg"

attach "$work/Ciel.dmg"
codesign --verify --strict --deep "$mountpoint/Ciel.app" || fail 'Ciel.app in the disk image fails codesign --verify.'
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
source_hash="$(cdhash "$app")"
[[ -n "$source_hash" && "$(cdhash "$mountpoint/Ciel.app")" == "$source_hash" ]] ||
    fail 'Ciel.app in the disk image has a different CDHash from the source app.'
[[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] ||
    fail 'Applications in the disk image is not a symlink to /Applications.'
cmp -s "$mountpoint/.background.tiff" "$work/background.tiff" ||
    fail 'The background in the disk image is not the picture this build drew.'
cmp -s "$mountpoint/.DS_Store" "$layout" || fail "The .DS_Store in the disk image is not $layout."
contents="$(cd "$mountpoint" && find . -mindepth 1 -maxdepth 1 | sort | tr '\n' ' ')"
[[ "$contents" == './.DS_Store ./.background.tiff ./Applications ./Ciel.app ' ]] ||
    fail "The disk image holds unexpected files: $contents"
detach

mkdir -p "$(dirname "$output")"
mv -f "$work/Ciel.dmg" "$output"
printf 'Built %s\n' "$output"
