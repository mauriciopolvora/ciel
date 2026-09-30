#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$HOME/Applications/Ciel.app"
legacy="$HOME/Applications/Jumpstart.app"
if [[ ! -d dist/Ciel.app ]]; then
    printf 'Build the app first: bash scripts/build.sh\n' >&2; exit 1
fi
for installed in "$destination/Contents/MacOS/Ciel" "$legacy/Contents/MacOS/Jumpstart"; do
    if pgrep -f "^${installed}( |$)" >/dev/null; then
        printf 'Quit the installed launcher from its menu bar menu before installing.\n' >&2; exit 1
    fi
done
codesign --verify --strict dist/Ciel.app
mkdir -p "$HOME/Applications" .build/backups
staging_dir="$(mktemp -d "$HOME/Applications/.ciel-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto dist/Ciel.app "$staging_dir/Ciel.app"
codesign --verify --strict "$staging_dir/Ciel.app"
backup="$PWD/.build/backups/install-$(date +%Y%m%d-%H%M%S)-$$"
if [[ -d "$destination" || -d "$legacy" ]]; then
    mkdir -p "$backup"
    if [[ -d "$destination" ]]; then mv "$destination" "$backup/Ciel.app"; fi
    if [[ -d "$legacy" ]]; then
        identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$legacy/Contents/Info.plist")
        if [[ "$identifier" == "app.mauriciopolvora.jumpstart" ]]; then mv "$legacy" "$backup/Jumpstart.app"; fi
    fi
    printf 'Previous app saved in %s\n' "$backup"
fi
mv "$staging_dir/Ciel.app" "$destination"
printf 'Installed %s\n' "$destination"
