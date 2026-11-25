#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-script-comments.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0
hash='#'
slashes='//'
pin="$(printf 'a%.0s' {1..40} | tr a 0)"

expect() {
    local want="$1" name="$2" file="$3" text="$4" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts" "$(dirname "$root/$file")"
    cp scripts/check-comments.mjs "$root/scripts/"
    printf '%s\n' "$text" >"$root/$file"
    git -C "$root" init -q
    [[ "${track:-yes}" == no ]] || git -C "$root" add -A
    output="$(node "$root/scripts/check-comments.mjs" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || ( "$want" -eq 1 && "$output" != *"$file:"* ) ]]; then
        printf 'FAIL %s: exit %s, expected %s. Output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "a script with no comments" scripts/a.sh $'#!/bin/bash\necho hi'
expect 1 "a shell comment line" scripts/a.sh "$hash says what it does"
expect 1 "an indented shell comment" scripts/a.sh $'if true; then\n    '"$hash"$' note\nfi'
expect 1 "a trailing shell comment" scripts/a.sh "echo hi $hash note"
expect 1 "a comment in a hook" .githooks/pre-push $'#!/usr/bin/env bash\n'"$hash note"
expect 1 "a comment in site shell" site/check.sh "$hash note"
expect 0 "a WARNING line" scripts/a.sh "$hash WARNING: git quotes odd names without -z."
expect 1 "a warning that is not at the start" scripts/a.sh "$hash note, WARNING: x"
expect 1 "a WARNING with no colon" scripts/a.sh "$hash WARNING git quotes odd names."
expect 1 "a lowercase warning" scripts/a.sh "$hash warning: git quotes odd names."
expect 1 "a shellcheck word with no directive" scripts/a.sh "$hash shellcheckdisable=SC2086"
expect 1 "a #! line after the first" scripts/a.sh $'echo hi\n'"$hash"'! note'
expect 0 "a shellcheck directive" scripts/a.sh "$hash shellcheck disable=SC2086"
expect 0 "a hash in quotes" scripts/a.sh $'echo "'"$hash"$' not a comment" \'a '"$hash"$' b\''
expect 0 "a hash in a heredoc" scripts/a.sh $'cat <<EOF\n'"$hash"$' text\nEOF'
expect 0 "hash parameter forms" scripts/a.sh 'echo $# ${#items[@]} ${name#prefix} ${name##*/}'
expect 0 "a hash inside a word" scripts/a.sh 'curl https://example.test/a#b'
expect 1 "a YAML comment" .github/workflows/x.yml $'name: x\n'"$hash"$' note\non: push'
expect 1 "a shell comment in a YAML run block" .github/workflows/x.yml $'jobs:\n  a:\n    steps:\n      - run: |\n          '"$hash"$' note\n          echo hi'
expect 0 "a pinned action version" .github/workflows/x.yml "      - uses: actions/checkout@$pin $hash v4.2.2"
expect 1 "a note after a pin" .github/workflows/x.yml "      - uses: actions/checkout@$pin $hash pinned"
expect 0 "a hash in a YAML string" .github/workflows/x.yml "name: \"a $hash b\""
expect 1 "a comment in .yaml" .github/dependabot.yaml "$hash note"
expect 1 "a JS line comment" site/a.js "$slashes note"
expect 1 "a trailing JS comment" site/a.js "run(); $slashes note"
expect 1 "a JS block comment" site/a.js '/* note */'
expect 1 "a JS block comment over lines" site/a.js $'/*\n * note\n */\nrun();'
expect 1 "an mjs comment" scripts/a.mjs "$slashes note"
expect 0 "slashes in a JS string" site/a.js "const url = \"https:${slashes}example.test\";"
expect 0 "slashes in a template" site/a.js "const url = \`https:${slashes}\${host}/\${\"$slashes\"}\`;"
expect 0 "a JS regex with slashes" site/a.js "const re = /\\/\\//; const n = a / b / c;"
expect 0 "a JS WARNING line" site/a.js "$slashes WARNING: Safari fires this twice."
expect 0 "a vendored file" site/public/assets/lenis/lenis.min.js "$slashes vendored"
expect 0 "a Swift file" Sources/A.swift "$slashes Swift is checked by lint-comments.sh"
track=no expect 0 "an untracked file" scripts/a.sh "$hash note"
output="$(node scripts/check-comments.mjs 2>&1)" || { printf 'FAIL the current tree:\n%s\n' "$output"; failures=$((failures + 1)); }

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-script-comments: %s cases failed\n' "$failures" >&2
    exit 1
fi
