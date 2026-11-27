#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-root.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0

expect() {
    local want="$1" name="$2" text="$3" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$root/Sources/Ciel" "$root/.github"
    cp scripts/lint/check-root.mjs "$root/scripts/lint/"
    printf '%s\n' .gitignore Package.swift Sources/ scripts/ >"$root/scripts/lint/root.txt"
    printf '.build/\ndist/\n' >"$root/.gitignore"
    printf 'x\n' >"$root/Package.swift"
    printf 'x\n' >"$root/Sources/Ciel/App.swift"
    printf 'x\n' >"$root/.github/dependabot.yml"
    git -C "$root" init -q
    git -C "$root" config core.excludesFile /dev/null
    (cd "$root" && eval "$4") ||
        { printf 'check-lint-root: %s: the command that breaks the copy failed.\n' "$name" >&2; exit 1; }
    output="$(node "$root/scripts/lint/check-root.mjs" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "the listed root" "" ":"
expect 1 "a root file not on the list" "notes.txt is not on the root list" 'printf x >notes.txt'
expect 1 "a root folder not on the list" "Tools/ is not on the root list" 'mkdir Tools && printf x >Tools/a.swift'
expect 1 "a listed entry the root does not have" "the root has no Package.swift" 'rm Package.swift'
expect 1 "a list line with a trailing space" "line 2 has a space" 'sed -i.bak "2s/$/ /" scripts/lint/root.txt && rm scripts/lint/root.txt.bak'
expect 1 "no list" "scripts/lint/root.txt is missing" 'rm scripts/lint/root.txt'
expect 1 "another lockfile, even on the list" "bun installs" 'printf x >package-lock.json && echo package-lock.json >>scripts/lint/root.txt'
expect 1 "a root tests folder" "the SwiftPM test target folder" 'mkdir tests && printf x >tests/a.swift'
expect 1 "a Renovate config in .github" ".github/renovate.json is not allowed" 'printf x >.github/renovate.json'
expect 1 "a knip config file" "the knip key in package.json" 'printf x >knip.json'
expect 1 "a folder named for a kind of file" "Sources/Ciel/utils/ is a folder named for a kind of file" 'mkdir Sources/Ciel/utils && printf x >Sources/Ciel/utils/a.swift'
expect 1 "a root symlink to a folder" "Linked/ is not on the root list" 'ln -s Sources Linked'
expect 0 "an ignored root folder" "" 'mkdir dist && printf x >dist/a'
expect 1 "another lockfile name" "bun installs" 'printf x >npm-shrinkwrap.json'
expect 0 "a nested file with an owned name" "" 'printf x >Sources/Ciel/yarn.lock'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-root: %s cases failed\n' "$failures" >&2
    exit 1
fi
