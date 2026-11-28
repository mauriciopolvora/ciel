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
    local want="$1" name="$2" text="$3" file="${4:-.github/workflows/x.yml}" root output status=0
    case_number=$((case_number + 1))
    root="$scratch/$case_number"
    mkdir -p "$root/scripts/lint" "$(dirname "$root/$file")"
    cp scripts/lint/check-git-auth.mjs "$root/scripts/lint/"
    printf '%s\n' "$5" >"$root/$file"
    git -C "$root" init -q
    git -C "$root" add -A
    if [[ -n "${nobun:-}" ]]; then
        mkdir "$root/nobun"
        ln -s "$(command -v node)" "$(command -v git)" "$root/nobun/"
        output="$(PATH="$root/nobun" node "$root/scripts/lint/check-git-auth.mjs" 2>&1)" || status=$?
    else
        output="$(node "$root/scripts/lint/check-git-auth.mjs" 2>&1)" || status=$?
    fi
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

expect 0 "a read-only workflow" "" "" "$read_only"
expect 0 "a write workflow that does not run the script" "" "" 'on: [push]
permissions:
  contents: write
jobs:
  a:
    steps:
      - run: gh api runs --jq ".workflow_runs[0]"'
expect 0 "a job with its own read-only permissions" "" "" "${read_only/permissions:
  contents: read/permissions: write-all}
    permissions: {contents: read}"
expect 0 "a write job that does not run the script" "" "" "$read_only
  release:
    permissions: {contents: write}
    steps:
      - run: echo"
expect 0 "a push on a branch named workflow_run" "" "" "${read_only/\[pull_request\]/
  push:
    branches: [workflow_run]}"
expect 1 "a job with write permissions" 'job check runs git-auth.sh with permissions {"contents":"write"}' "" "$read_only
    permissions:
      contents: write"
expect 1 "a quoted permissions key on a job" 'job check runs' "" "$read_only
    'permissions': {contents: write}"
expect 1 "a spaced permissions key on a job" 'job check runs' "" "$read_only
    permissions : {contents: write}"
expect 1 "a flow-style job" 'job check runs' "" 'on: [push]
permissions:
  contents: read
jobs:
  check: {permissions: {contents: write}, steps: [{run: bash scripts/git-auth.sh}]}'
expect 1 "a write scope at the top" 'permissions {"contents":"write"}' "" "${read_only/contents: read/contents: write}"
expect 1 "a second scope at the top" '{"contents":"read","actions":"read"}' "" "${read_only/contents: read/contents: read
  actions: read}"
expect 1 "read-all at the top" 'permissions "read-all"' "" "${read_only/permissions:
  contents: read/permissions: read-all}"
expect 1 "no permissions" 'permissions null' "" "${read_only/permissions:
  contents: read/}"
expect 1 "the script from its own folder" 'job check runs' "" "${read_only/      - run: bash scripts\/git-auth.sh/      - run: bash git-auth.sh
        working-directory: scripts}
    permissions: {contents: write}"
inline='permissions: {contents: read}'
expect 0 "inline read-only permissions at the top" "" "" "${read_only/permissions:
  contents: read/$inline}"
expect 0 "a YAML comment in the permissions block" "" "" "${read_only/  contents: read/  # contents: write
  contents: read}"
expect 1 "the script named in the workflow env" 'job release runs' "" 'on: [push]
permissions:
  contents: read
env:
  AUTH: scripts/git-auth.sh
jobs:
  release:
    permissions: {contents: write}
    steps:
      - run: bash "$AUTH"'
expect 1 "a workflow_call workflow" 'starts on workflow_call' "" "${read_only/\[pull_request\]/[workflow_call]}"
expect 1 "a pull_request_target run" 'starts on pull_request_target' "" "${read_only/pull_request/pull_request_target}"
expect 1 "a pull_request_target string" 'starts on pull_request_target' "" "${read_only/on: \[pull_request\]/on: pull_request_target}"
quoted_on="'on':
- workflow_run"
expect 1 "a quoted on key with workflow_run" 'starts on workflow_run' "" "${read_only/on: \[pull_request\]/$quoted_on}"
expect 1 "a workflow_run map" 'starts on workflow_run' "" "${read_only/\[pull_request\]/
  workflow_run:
    workflows: [x]}"
composite='runs:
  using: composite
  steps:
    - run: bash scripts/git-auth.sh
      shell: bash'
expect 1 "a workflow file outside .github/workflows" 'ci/x.yml names git-auth.sh' ci/x.yml "$read_only"
expect 1 "a composite action outside .github" 'scripts/auth/action.yml names git-auth.sh' scripts/auth/action.yml "$composite"
expect 1 "a composite action under workflows" '.github/workflows/auth/action.yml names git-auth.sh' .github/workflows/auth/action.yml "$composite"
expect 1 "a composite action that runs the script" '.github/actions/auth/action.yml names git-auth.sh' .github/actions/auth/action.yml 'runs:
  using: composite
  steps:
    - run: bash scripts/git-auth.sh
      shell: bash'
nobun=1 expect 2 "no bun" 'bun did not parse' "" "$read_only"

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-git-auth: %s cases failed\n' "$failures" >&2
    exit 1
fi
