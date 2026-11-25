#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-paths.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0

expect() {
    local want="$1" name="$2" file="$3" text="$4" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$root/.agents/skills/v/scripts"
    cp scripts/lint/lint-paths.sh "$root/scripts/lint/"
    printf 'echo run\n' >"$root/scripts/real.sh"
    printf 'echo run\n' >"$root/scripts/lint/check-lint-paths.sh"
    printf 'echo run\n' >"$root/.agents/skills/v/scripts/run.sh"
    mkdir -p "$(dirname "$root/$file")"
    printf '%s\n' "$text" >"$root/$file"
    git -C "$root" init -q
    git -C "$root" add -A
    [[ -z "${untracked:-}" ]] || printf 'echo run\n' >"$root/$untracked"
    output="$(bash "$root/scripts/lint/lint-paths.sh" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" ]]; then
        printf 'FAIL %s: exit %s, expected %s. Lint output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "a tracked path" README.md 'Run `bash scripts/real.sh`.'
expect 1 "a missing path in README.md" README.md 'Run `bash scripts/missing.sh`.'
expect 1 "a missing path in AGENTS.md" AGENTS.md '- bash scripts/missing.sh runs it.'
expect 1 "a missing path in CONTRIBUTING.md" CONTRIBUTING.md 'Run scripts/missing.sh'
expect 1 "a missing path in docs" docs/guide.md '(scripts/missing.sh)'
expect 1 "a missing path in a workflow" .github/workflows/x.yml '        run: bash scripts/missing.sh'
expect 1 "a missing path in a hook" .githooks/pre-push 'bash scripts/missing.sh'
expect 1 "a missing path in a script" scripts/other.sh 'bash scripts/missing.sh'
expect 1 "a missing path at the start of a line" docs/guide.md 'scripts/missing.sh runs it.'
expect 1 "a missing path after ./" README.md 'Run `bash ./scripts/missing.sh`.'
expect 1 "a missing path after ./ at the start of a line" docs/guide.md './scripts/missing.sh runs it.'
expect 0 "a tracked path after ./" README.md 'Run `bash ./scripts/real.sh`.'
expect 1 "a missing path after ./ in a skill" .agents/skills/v/SKILL.md 'Run ./scripts/gone.sh.'
expect 0 "a skill path after ./ from the skill root" .agents/skills/v/SKILL.md 'Run ./scripts/run.sh.'
expect 0 "a path at the end of a sentence" docs/guide.md 'Run scripts/real.sh.'
expect 0 "a glob that matches" docs/guide.md 'Every scripts/*.sh file.'
expect 1 "a glob that matches nothing" docs/guide.md 'Every scripts/*.py file.'
expect 0 "a skill path from the repo root" README.md 'bash .agents/skills/v/scripts/run.sh'
expect 1 "a missing skill path" README.md 'bash .agents/skills/v/scripts/gone.sh'
expect 0 "a skill path from the skill root" .agents/skills/v/SKILL.md 'Run scripts/run.sh.'
expect 1 "a missing path in a skill" .agents/skills/v/SKILL.md 'Run scripts/gone.sh.'
expect 1 "a skill path outside that skill" README.md 'Run scripts/run.sh.'
expect 0 "a URL" README.md 'https://example.test/scripts/missing.sh'
expect 0 "a path under a variable" scripts/other.sh '"$here/scripts/missing.sh"'
expect 0 "a file outside the scanned set" Sources/Other.swift '"scripts/missing.sh"'
expect 0 "a lint self-test" scripts/lint/check-lint-other.sh 'bash scripts/missing.sh'
untracked=scripts/new.sh expect 1 "a path to an untracked file" README.md 'Run scripts/new.sh'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-paths: %s cases failed\n' "$failures" >&2
    exit 1
fi
