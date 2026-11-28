#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-git-auth.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
case_number=0

read_only='on: [pull_request]
permissions:
  contents: read
jobs:
  check:
    runs-on: macos-15
    steps:
      - run: bash scripts/git-auth.sh'

expect() {
    local want="$1" name="$2" text="$3" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$root/.github/workflows"
    cp scripts/lint/lint-git-auth.sh "$root/scripts/lint/"
    printf '%s\n' "$text" >"$root/.github/workflows/x.yml"
    git -C "$root" init -q
    git -C "$root" add -A
    output="$(bash "$root/scripts/lint/lint-git-auth.sh" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" ]]; then
        printf 'FAIL %s: exit %s, expected %s. Lint output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "a read-only workflow" "$read_only"
expect 0 "a workflow that does not run the script" 'on: [push]
permissions:
  contents: write'
expect 1 "a job with its own permissions" "$read_only
    permissions:
      contents: write"
expect 1 "a write scope at the top" "${read_only/contents: read/contents: write}"
expect 1 "a second scope at the top" "${read_only/contents: read/contents: read
  actions: read}"
expect 1 "read-all at the top" "${read_only/permissions:
  contents: read/permissions: read-all}"
expect 1 "no top permissions" "${read_only/permissions:
  contents: read/}"
expect 1 "an empty top permissions block" "${read_only/  contents: read/}"
expect 1 "a pull_request_target run" "${read_only/pull_request/pull_request_target}"
expect 1 "a workflow_run run" "${read_only/[pull_request]/
  workflow_run:
    workflows: [x]}"
expect 0 "a comment that names a write scope" "$read_only
      # permissions: contents: write"
expect 0 "a step that reads workflow_runs" "$read_only
      - run: gh api runs --jq '.workflow_runs[0]'"

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-git-auth: %s cases failed\n' "$failures" >&2
    exit 1
fi
