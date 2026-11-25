#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-docs.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
dash="$(printf '\342\200\224')"

git ls-files -z -- '*.md' .claude scripts/lint/check-docs.mjs >"$scratch/listed"
tar -cf "$scratch/repo.tar" --null -T "$scratch/listed"

expect() {
    local want="$1" name="$2" text="$3" root="$scratch/repo" output status=0
    rm -rf "$root" && mkdir "$root" && tar -xf "$scratch/repo.tar" -C "$root"
    git -C "$root" init -q && git -C "$root" add -A
    (cd "$root" && eval "$4") ||
        { printf 'check-lint-docs: %s: the command that breaks the copy failed.\n' "$name" >&2; exit 1; }
    output="$(node "$root/scripts/lint/check-docs.mjs" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "the current docs" "" ":"
expect 1 "an em dash in a doc" "README.md:$(($(wc -l <README.md) + 1)):a $dash b" 'printf "a %s b\n" "$dash" >>README.md'
expect 1 "an em dash in a script" "scripts/x.sh:1:echo $dash" 'mkdir -p scripts && printf "echo %s\n" "$dash" >scripts/x.sh && git add scripts/x.sh'
expect 0 "an em dash in an untracked file" "" 'printf "a %s b\n" "$dash" >notes.txt'
expect 1 "a doc not on the list" "docs/new.md is not on the docs list" 'printf "# New\n" >docs/new.md && git add docs/new.md'
expect 1 "a doc over its cap" "docs/artwork.md has" 'for i in $(seq 20); do echo line; done >>docs/artwork.md'
expect 1 "a listed doc git does not track" "docs/artwork.md is on the docs list" 'rm docs/artwork.md'
expect 1 "AGENTS.md over 4096 bytes" "byte cap" 'head -c 4097 /dev/zero | tr "\0" a >>AGENTS.md'
expect 1 "a CLAUDE.md file" "CLAUDE.md must be a symlink" 'rm CLAUDE.md && cp AGENTS.md CLAUDE.md'
expect 1 "a CLAUDE.md link to another file" "CLAUDE.md must be a symlink" 'ln -sfn README.md CLAUDE.md'
expect 1 "no AGENTS.md" "AGENTS.md is missing" 'rm AGENTS.md'
expect 1 "a skill with no .claude link" ".claude/skills/verify-ciel must be a symlink" 'rm .claude/skills/verify-ciel'
expect 1 "a .claude link with no skill" "has no .agents/skills/ghost" 'ln -s ../../.agents/skills/ghost .claude/skills/ghost'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-docs: %s cases failed\n' "$failures" >&2
    exit 1
fi
