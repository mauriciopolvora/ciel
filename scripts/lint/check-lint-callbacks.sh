#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

scratch=$(mktemp -d)
trap 'chmod -R u+rwx "$scratch"; rm -rf "$scratch"' EXIT
failures=0

expect() {
    local output status=0
    output=$(bash "$3/scripts/lint/lint-callbacks.sh" 2>&1) || status=$?
    if [ "$status" -ne "$1" ]; then
        echo "FAIL $2: exit $status, expected $1. Lint output:"
        echo "$output"
        failures=$((failures + 1))
    fi
}

tree() {
    local root="$scratch/$1"
    mkdir -p "$root/scripts/lint" "$root/Sources/Ciel" "$root/Tests" "$(dirname "$root/$2")"
    cp scripts/lint/lint-callbacks.sh "$root/scripts/lint/"
    printf '%s\n' "$3" > "$root/$2"
    echo "$root"
}

other=Sources/Ciel/Other.swift
calls=(
    'NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in }'
    'if let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: config) { _ = app }'
    'NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: (handler))'
    'AVCaptureDevice.requestAccess(for: .audio, completionHandler: ready ? onReady : onWait)'
    'PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: { status in })'
    'UNUserNotificationCenter.current().getNotificationSettings(completionHandler: handler)'
    'URLSession.shared.dataTask(with: url) { data, response, error in }'
    'node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in }'
    'NSAnimationContext.runAnimationGroup({ $0.duration = 0.16 }) { done() }'
    'NSAnimationContext.runAnimationGroup { $0.duration = 0.16 }'
    'UNUserNotificationCenter.current().getNotificationSettings { settings in }'
    'NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: handler)'
)
i=0
for call in "${calls[@]}"; do
    i=$((i + 1))
    expect 1 "call $i outside the wrapper: $call" "$(tree "call$i" "$other" "$call")"
    expect 0 "call $i inside the wrapper: $call" "$(tree "wrapped$i" Sources/Ciel/App/OffMainCallbacks.swift "$call")"
done
expect 1 "a call in Tests" "$(tree tests Tests/MicrophoneTests.swift 'AVCaptureDevice.requestAccess(for: .audio) { _ in }')"
expect 0 "a call in a comment" "$(tree comment "$other" '    // NSWorkspace.shared.openApplication(at: url)')"
expect 0 "the current tree" "$PWD"

missing=$(tree missing "$other" 'let x = 1')
rm -rf "$missing/Sources"
expect 2 "a missing Sources" "$missing"
if [ "$(id -u)" -ne 0 ]; then
    unreadable=$(tree unreadable "$other" 'let x = 1')
    chmod 000 "$unreadable/Sources/Ciel"
    expect 2 "an unreadable Sources folder" "$unreadable"
fi

if [ "$failures" -ne 0 ]; then
    echo "check-lint-callbacks: $failures case(s) failed"
    exit 1
fi
echo "check-lint-callbacks: all cases pass"
