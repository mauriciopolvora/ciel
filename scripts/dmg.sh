#!/bin/bash
set -euo pipefail
# With CDPATH set, cd prints the directory and corrupts the paths read from it.
unset CDPATH
fail() { printf '%s\n' "$1" >&2; exit 1; }
if [[ $# -ne 2 ]]; then fail 'Usage: bash scripts/dmg.sh path/to/Ciel.app output.dmg'; fi
[[ -d "$1" && "$(basename "$1")" == Ciel.app ]] || fail "$1 is not a Ciel.app bundle."
app="$(cd "$1" && pwd)"
if [[ "$2" == /* ]]; then output="$2"; else output="$PWD/$2"; fi
cd "$(dirname "$0")/.."
# Window geometry in points. The background and the Finder layout both read it from here.
width=640
height=380
icon_size=128
text_size=13
icon_y=172
app_x=172
applications_x=468

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

swift scripts/GenerateDMGBackground.swift Resources/CloudPainting.png "$work" \
    "$width" "$height" "$icon_size" "$icon_y" "$app_x" "$applications_x"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" 2>/dev/null
"$venv/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app="$app" -D background="$work/background.tiff" \
    -D width="$width" -D height="$height" -D icon_size="$icon_size" -D text_size="$text_size" \
    -D icon_y="$icon_y" -D app_x="$app_x" -D applications_x="$applications_x" \
    Ciel "$work/Ciel.dmg" >/dev/null

mkdir "$mountpoint"
hdiutil attach "$work/Ciel.dmg" -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" -quiet
attached=true
codesign --verify --strict --deep "$mountpoint/Ciel.app" || fail 'Ciel.app in the disk image fails codesign --verify.'
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
source_hash="$(cdhash "$app")"
[[ -n "$source_hash" && "$(cdhash "$mountpoint/Ciel.app")" == "$source_hash" ]] ||
    fail 'Ciel.app in the disk image has a different CDHash from the source app.'
[[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] ||
    fail 'Applications in the disk image is not a symlink to /Applications.'
[[ "$(sips -g pixelWidth "$mountpoint/.background.tiff" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "$width" ]] ||
    fail "The background in the disk image is not a $width point wide picture."
"$venv/bin/python" - "$mountpoint/.DS_Store" "$app_x" "$applications_x" "$icon_y" <<'PYTHON' ||
import sys
from ds_store import DSStore

app_x, applications_x, icon_y = map(int, sys.argv[2:])
with DSStore.open(sys.argv[1], "r") as store:
    placed = store["Ciel.app"]["Iloc"] == (app_x, icon_y) and store["Applications"]["Iloc"] == (applications_x, icon_y)
    pictured = store["."]["icvp"]["backgroundType"] == 2
sys.exit(not (placed and pictured))
PYTHON
    fail 'The .DS_Store in the disk image does not place both icons on the background picture.'
contents="$(cd "$mountpoint" && find . -mindepth 1 -maxdepth 1 | LC_ALL=C sort | tr '\n' ' ')"
[[ "$contents" == './.DS_Store ./.background.tiff ./Applications ./Ciel.app ' ]] ||
    fail "The disk image holds unexpected files: $contents"
hdiutil detach "$mountpoint" -quiet
attached=false

mkdir -p "$(dirname "$output")"
mv -f "$work/Ciel.dmg" "$output"
printf 'Built %s\n' "$output"
