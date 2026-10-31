#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--unit-only" ) ]]; then
    printf 'Usage: bash scripts/check.sh [--unit-only]\n' >&2; exit 1
fi
bash -n scripts/*.sh
plutil -lint Resources/Info.plist Resources/Ciel.entitlements
swift format lint --strict --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
bash scripts/lint-colors.sh
bash scripts/test.sh -c release -Xswiftc -warnings-as-errors
bash scripts/benchmark.sh
if [[ $# -eq 1 ]]; then exit 0; fi
bash scripts/build.sh
check_dir="$(mktemp -d "$PWD/.build/ciel-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
copy_app() {
    ditto dist/Ciel.app "$1"
    /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $2" "$1/Contents/Info.plist"
    codesign --force --sign - --preserve-metadata=entitlements,flags "$1"
}
check_identifier="$(plutil -extract CFBundleIdentifier raw Resources/Info.plist).checks"
copy_app "$check_dir/CielChecks.app" "$check_identifier"
copy_app "$check_dir/OtherIdentity.app" "$check_identifier.other"
identity_status=0
"$check_dir/OtherIdentity.app/Contents/MacOS/Ciel" --catalog-test 2>/dev/null || identity_status=$?
if [[ $identity_status -ne 64 ]]; then
    printf "A native check ran outside %s and exited %d instead of 64.\n" "$check_identifier" "$identity_status" >&2
    exit 1
fi
check_binary="$check_dir/CielChecks.app/Contents/MacOS/Ciel"
"$check_binary" --ui-test
"$check_binary" --catalog-test
CIEL_SMOKE_OUTPUT="$PWD/.build/smoke" "$check_binary" --smoke-test
CIEL_PERFORMANCE_OUTPUT="$PWD/.build/performance/native-ui.json" "$check_binary" --performance-test
window_status=0
"$check_binary" --window-test || window_status=$?
if [[ $window_status -eq 2 && -z "${CI:-}" ]]; then
    printf 'Skipped the window test: grant Accessibility access to the app that runs this script, such as your terminal. CI fails on this skip.\n' >&2
elif [[ $window_status -ne 0 ]]; then
    exit "$window_status"
fi
