#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$HOME/Applications/Ciel.app"
if [[ ! -d dist/Ciel.app ]]; then
    printf 'Build the app first: bash scripts/build.sh\n' >&2; exit 1
fi
if pgrep -f "^${destination}/Contents/MacOS/Ciel( |$)" >/dev/null; then
    printf 'Quit the installed launcher from its menu bar menu before installing.\n' >&2; exit 1
fi
codesign --verify --strict dist/Ciel.app
mkdir -p "$HOME/Applications" .build/backups
staging_dir="$(mktemp -d "$HOME/Applications/.ciel-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto dist/Ciel.app "$staging_dir/Ciel.app"
codesign --verify --strict "$staging_dir/Ciel.app"
if [[ -d "$destination" ]]; then
    backup="$PWD/.build/backups/install-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$backup"
    mv "$destination" "$backup/Ciel.app"
    printf 'Previous app saved in %s\n' "$backup"
fi
mv "$staging_dir/Ciel.app" "$destination"
printf 'Installed %s\n' "$destination"
