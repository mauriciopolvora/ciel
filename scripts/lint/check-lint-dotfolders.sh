#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-dotfolders.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0

expect() {
    local want="$1" name="$2" text="$3" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$root/.github"
    cp scripts/lint/check-dotfolders.mjs "$root/scripts/lint/"
    printf '.github\n' >"$root/scripts/lint/dotfolders.txt"
    printf '.build/\n' >"$root/.gitignore"
    printf 'x\n' >"$root/.github/dependabot.yml"
    git -C "$root" init -q
    git -C "$root" config core.excludesFile /dev/null
    (cd "$root" && eval "$4") ||
        { printf 'check-lint-dotfolders: %s: the command that breaks the copy failed.\n' "$name" >&2; exit 1; }
    output="$(node "$root/scripts/lint/check-dotfolders.mjs" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "the listed dotfolders" "" ":"
expect 1 "a dotfolder not on the list" ".config/ is not on the dotfolder list" 'mkdir .config && printf x >.config/a'
expect 1 "a nested dotfolder not on the list" "site/.cache/ is not on the dotfolder list" 'mkdir -p site/.cache && printf x >site/.cache/a'
expect 1 "an editor folder, even on the list" ".vscode/ is not allowed" 'mkdir .vscode && printf x >.vscode/settings.json && echo .vscode >>scripts/lint/dotfolders.txt'
expect 1 "another agent rules folder" ".cursor/ is not allowed" 'mkdir .cursor && printf x >.cursor/rules'
expect 1 "a listed folder with no file" ".agents is on the dotfolder list" 'echo .agents >>scripts/lint/dotfolders.txt'
expect 1 "a list line with a trailing space" "line 1 has a space" 'printf ".github \n" >scripts/lint/dotfolders.txt'
expect 1 "no list" "scripts/lint/dotfolders.txt is missing" 'rm scripts/lint/dotfolders.txt'
expect 1 "a symlink to a dotfolder" ".linked/ is not on the dotfolder list" 'ln -s .github .linked'
expect 0 "an ignored dotfolder" "" 'mkdir .build && printf x >.build/a'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-dotfolders: %s cases failed\n' "$failures" >&2
    exit 1
fi
