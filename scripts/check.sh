#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--unit-only" ) ]]; then
    printf 'Usage: bash scripts/check.sh [--unit-only]\n' >&2; exit 1
fi
bash -n scripts/*.sh
plutil -lint Resources/Info.plist Resources/Ciel.entitlements
if [[ "$(plutil -extract SUFeedURL raw Resources/Info.plist)" != https://* ]] ||
    ! plutil -extract SUPublicEDKey raw Resources/Info.plist | grep -qE '^[A-Za-z0-9+/]{43}=$'; then
    printf 'Info.plist needs an https SUFeedURL and a base64 Ed25519 SUPublicEDKey for updates.\n' >&2; exit 1
fi
swift format lint --strict --recursive Sources Tests scripts/GenerateIcon.swift scripts/VerifyUpdate.swift Package.swift
bash scripts/lint-colors.sh
bash scripts/test.sh -c release -Xswiftc -warnings-as-errors
bash scripts/benchmark.sh
bash scripts/check-appcast.sh
if [[ $# -eq 1 ]]; then exit 0; fi
bash scripts/build.sh
if [[ ! -d dist/Ciel.app/Contents/Frameworks/Sparkle.framework ]]; then
    printf 'The built app has no Sparkle.framework, so it cannot update itself.\n' >&2; exit 1
fi
codesign --verify --strict --deep dist/Ciel.app
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
if [[ -n "${CIEL_SPEECH_MODEL:-}" ]]; then
    speech_status=0
    "$check_binary" --speech-quit-test || speech_status=$?
    if [[ $speech_status -ne 0 ]]; then
        printf 'Quitting with the speech model loaded exited %d instead of 0.\n' "$speech_status" >&2
        exit 1
    fi
    printf 'PASS quitting with the speech model loaded exits 0\n'
else
    printf 'Skipped the speech quit test: set CIEL_SPEECH_MODEL to a speech model file to run it.\n' >&2
fi
window_status=0
"$check_binary" --window-test || window_status=$?
if [[ $window_status -eq 2 && -z "${CI:-}" ]]; then
    printf 'Skipped the window test: grant Accessibility access to the app that runs this script, such as your terminal. CI fails on this skip.\n' >&2
elif [[ $window_status -ne 0 ]]; then
    exit "$window_status"
fi
