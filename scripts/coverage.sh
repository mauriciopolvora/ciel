#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
[[ $# -eq 0 ]] || {
    printf 'Usage: bash scripts/coverage.sh\nRuns the unit tests with code coverage and writes .build/coverage/summary.md, report.txt and html/.\n' >&2
    exit 64
}

command -v jq >/dev/null || { printf 'coverage.sh needs jq on the PATH to write the summary.\n' >&2; exit 1; }

bash scripts/test.sh --enable-code-coverage
bin="$(swift build --show-bin-path)"
profile="$bin/codecov/default.profdata"
tests="$bin/CielPackageTests.xctest/Contents/MacOS/CielPackageTests"
out=.build/coverage
rm -rf "$out"
mkdir -p "$out"
cov=("-instr-profile=$profile" "$tests" "$PWD/Sources")

xcrun llvm-cov report "${cov[@]}" >"$out/report.txt"
xcrun llvm-cov show -format=html -output-dir="$out/html" "${cov[@]}"
xcrun llvm-cov export -summary-only "${cov[@]}" >"$out/summary.json"
bash scripts/coverage-summary.sh "$out/summary.json" "$PWD/" >"$out/summary.md"
cat "$out/summary.md"
[[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || cat "$out/summary.md" >>"$GITHUB_STEP_SUMMARY"
