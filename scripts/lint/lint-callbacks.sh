#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."

wrapper=Sources/Ciel/App/OffMainCallbacks.swift
apis='openApplication[(]|[.]requestAccess[(]|requestAuthorization[(]|completionHandler|installTap[(]'
apis="$apis|runAnimationGroup|getNotificationSettings"
apis="$apis|(data|download|upload)Task[(]"

if ! list=$(find Sources Tests -name '*.swift' -type f ! -path "$wrapper"); then
    echo "lint-callbacks: cannot read Sources or Tests" >&2
    exit 2
fi
[ -n "$list" ] || exit 0
files=()
while IFS= read -r file; do files+=("$file"); done <<< "$list"

awk -v apis="$apis" -v wrapper="$wrapper" '
    /^[[:space:]]*(\/\/|\/\*|\*)/ { next }
    $0 ~ apis {
        print FILENAME ":" FNR ": an Apple API that runs its handler off the main thread. Call it through " \
            wrapper ", and add a wrapper there with an @escaping @Sendable handler if none fits." \
            " For a handler parameter of your own, use a name other than completionHandler."
        failed = 1
    }
    END { exit failed }
' "${files[@]}"
status=$?
[ "$status" -le 1 ] || { echo "lint-callbacks: cannot read a Swift file" >&2; exit 2; }
exit "$status"
