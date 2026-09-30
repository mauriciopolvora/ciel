#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--core-only" ) ]]; then
    printf 'Usage: bash scripts/check.sh [--core-only]\n' >&2; exit 1
fi
bash -n scripts/*.sh
plutil -lint Resources/Info.plist
swift format lint --strict --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
swift run -c release CielChecks
if [[ "${1:-}" == "--core-only" ]]; then exit 0; fi
bash scripts/build.sh
# Give native checks a separate identity so they do not read or write user settings.
check_dir="$(mktemp -d "$PWD/.build/ciel-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
check_app="$check_dir/CielChecks.app"
ditto dist/Ciel.app "$check_app"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier app.mauriciopolvora.ciel.checks' "$check_app/Contents/Info.plist"
codesign --force --sign - --options runtime "$check_app"
check_binary="$check_app/Contents/MacOS/Ciel"
"$check_binary" --ui-test
"$check_binary" --catalog-test
CIEL_SMOKE_OUTPUT="$PWD/.build/smoke" "$check_binary" --smoke-test
