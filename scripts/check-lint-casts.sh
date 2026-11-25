#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-casts.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0

expect() {
    local want="$1" name="$2" root="$3" output status=0
    output="$(bash "$root/scripts/lint-casts.sh" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" ]]; then
        printf 'FAIL %s: exit %s, expected %s. Lint output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

tree() {
    local root="$scratch/$1" path="$2" count="$3" line="$4"
    mkdir -p "$root/scripts" "$root/Sources/Ciel" "$(dirname "$root/$path")"
    cp scripts/lint-casts.sh "$root/scripts/"
    printf 'let ok = 1\n' >"$root/Sources/Ciel/Clean.swift"
    : >"$root/$path"
    for ((i = 0; i < count; i++)); do printf '%s\n' "$line" >>"$root/$path"; done
    git -C "$root" init -q
    git -C "$root" add -A
    printf '%s\n' "$root"
}

cast='let element = value as! AXUIElement'
expect 1 "as! in Sources" "$(tree sources Sources/Ciel/Other.swift 1 "$cast")"
expect 1 "as! in Tests" "$(tree tests Tests/CielAppTests/OtherTests.swift 1 "$cast")"
expect 1 "as! in scripts" "$(tree scripts scripts/GenerateIcon.swift 1 "$cast")"
expect 1 "as! at the start of a line" "$(tree start Sources/Ciel/Other.swift 1 'as! AXUIElement')"
expect 1 "two as! on one line" "$(tree pair Sources/Ciel/WindowAccessibility.swift 3 'f(a as! A, b as! B)')"
expect 0 "4 as! in WindowAccessibility.swift" "$(tree four Sources/Ciel/WindowAccessibility.swift 4 "$cast")"
expect 1 "5 as! in WindowAccessibility.swift" "$(tree five Sources/Ciel/WindowAccessibility.swift 5 "$cast")"
expect 0 "a moved WindowAccessibility.swift" "$(tree moved Sources/Window/WindowAccessibility.swift 4 "$cast")"
expect 1 "4 as! in another file" "$(tree other Sources/Ciel/WindowAccess.swift 4 "$cast")"
expect 0 "as?" "$(tree optional Sources/Ciel/Other.swift 1 'let element = value as? AXUIElement')"
expect 0 "a force unwrap" "$(tree unwrap Sources/Ciel/Other.swift 1 'let frame = canvas!.frame')"
untracked="$(tree untracked Sources/Ciel/Other.swift 0 '')"
printf '%s\n' "$cast" >"$untracked/Sources/Ciel/New.swift"
expect 0 "an untracked file" "$untracked"
expect 0 "the current tree" .

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-casts: %s cases failed\n' "$failures" >&2
    exit 1
fi
