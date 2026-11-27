#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-bunfig.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0

expect() {
    local want="$1" name="$2" text="$3" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$root/site"
    cp scripts/lint/check-bunfig.mjs "$root/scripts/lint/"
    printf '{}\n' >"$root/package.json"
    printf '{}\n' >"$root/site/package.json"
    printf '[install]\nminimumReleaseAge = 604800\n' >"$root/bunfig.toml"
    printf '[install]\nminimumReleaseAge = 604800\n' >"$root/site/bunfig.toml"
    printf 'node_modules/\n' >"$root/.gitignore"
    git -C "$root" init -q
    git -C "$root" config core.excludesFile /dev/null
    (cd "$root" && eval "$4") ||
        { printf 'check-lint-bunfig: %s: the command that breaks the copy failed.\n' "$name" >&2; exit 1; }
    output="$(node "$root/scripts/lint/check-bunfig.mjs" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "a 7 day gate next to each package.json" "" ":"
expect 0 "a longer gate and other install keys" "" 'printf "[install]\nexact = true\nminimumReleaseAge = 1209600\n" >site/bunfig.toml'
expect 1 "no bunfig.toml in a nested folder" "site/package.json has no site/bunfig.toml" 'rm site/bunfig.toml'
expect 1 "no bunfig.toml at the root" "./package.json has no bunfig.toml" 'rm bunfig.toml'
expect 1 "a new nested package.json" "e2e/package.json has no e2e/bunfig.toml" 'mkdir e2e && printf "{}\n" >e2e/package.json'
expect 1 "a gate shorter than 7 days" "site/bunfig.toml must set minimumReleaseAge = 604800" 'printf "[install]\nminimumReleaseAge = 259200\n" >site/bunfig.toml'
expect 1 "the gate outside the install table" "bunfig.toml must set minimumReleaseAge" 'printf "[run]\nminimumReleaseAge = 604800\n" >bunfig.toml'
expect 1 "the gate as a string" "bunfig.toml must set minimumReleaseAge" 'printf "[install]\nminimumReleaseAge = \"7d\"\n" >bunfig.toml'
expect 0 "an ignored package.json" "" 'mkdir -p node_modules/x && printf "{}\n" >node_modules/x/package.json'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-bunfig: %s cases failed\n' "$failures" >&2
    exit 1
fi
