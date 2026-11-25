#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 0 ]] || {
    printf 'Usage: bash scripts/coverage.sh\nRuns the unit tests with code coverage and writes .build/coverage/summary.md, report.txt and html/.\n' >&2
    exit 64
}

bash scripts/test.sh --enable-code-coverage
bin="$(swift build --show-bin-path)"
profile="$bin/codecov/default.profdata"
tests="$bin/CielPackageTests.xctest/Contents/MacOS/CielPackageTests"
out=.build/coverage
rm -rf "$out"
mkdir -p "$out"
cov=("$tests" "-instr-profile=$profile" "-ignore-filename-regex=/(\.build|Tests)/")

xcrun llvm-cov report "${cov[@]}" >"$out/report.txt"
xcrun llvm-cov show "${cov[@]}" -format=html -output-dir="$out/html"
xcrun llvm-cov export "${cov[@]}" -summary-only >"$out/summary.json"
bash scripts/coverage-summary.sh "$out/summary.json" "$PWD/" >"$out/summary.md"
cat "$out/summary.md"
[[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || cat "$out/summary.md" >>"$GITHUB_STEP_SUMMARY"
