#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--unit-only" ) ]]; then
    printf 'Usage: bash scripts/check.sh [--unit-only]\n' >&2; exit 1
fi
bash -n scripts/*.sh
plutil -lint Resources/Info.plist
swift format lint --strict --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
bash scripts/test.sh -c release -Xswiftc -warnings-as-errors
bash scripts/benchmark.sh
if [[ $# -eq 1 ]]; then exit 0; fi
bash scripts/build.sh
check_dir="$(mktemp -d "$PWD/.build/ciel-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
check_app="$check_dir/CielChecks.app"
ditto dist/Ciel.app "$check_app"
check_identifier="$(plutil -extract CFBundleIdentifier raw Resources/Info.plist).checks"
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $check_identifier" "$check_app/Contents/Info.plist"
codesign --force --sign - --options runtime "$check_app"
check_binary="$check_app/Contents/MacOS/Ciel"
"$check_binary" --ui-test
"$check_binary" --catalog-test
CIEL_SMOKE_OUTPUT="$PWD/.build/smoke" "$check_binary" --smoke-test
CIEL_PERFORMANCE_OUTPUT="$PWD/.build/performance/native-ui.json" "$check_binary" --performance-test
window_status=0
"$check_binary" --window-test || window_status=$?
if [[ $window_status -eq 2 && -z "${CI:-}" ]]; then
    printf 'Skipped the window test: the checks app has no Accessibility access here. CI fails on this skip.\n' >&2
elif [[ $window_status -ne 0 ]]; then
    exit "$window_status"
fi
