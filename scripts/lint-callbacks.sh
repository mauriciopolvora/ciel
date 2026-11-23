#!/bin/bash
# Fails when Swift code calls an Apple API that runs its handler off the main thread anywhere but
# Sources/Ciel/OffMainCallbacks.swift. That file types each handler @Sendable, so the compiler rejects a main actor
# closure, which traps on entry. The check matches names only, so it also flags a safe form, such as the async
# openApplication. Exit 0: clean. Exit 1: a call outside the wrapper file. Exit 2: Sources or Tests is unreadable.
set -uo pipefail
cd "$(dirname "$0")/.."

wrapper=Sources/Ciel/OffMainCallbacks.swift
apis='openApplication[(]|[.]requestAccess[(]|requestAuthorization[(]|completionHandler|installTap[(]'
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
            wrapper ", and add a wrapper there with an @escaping @Sendable handler if none fits."
        failed = 1
    }
    END { exit failed }
' "${files[@]}"
status=$?
[ "$status" -le 1 ] || { echo "lint-callbacks: cannot read a Swift file" >&2; exit 2; }
exit "$status"
