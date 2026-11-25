#!/bin/bash
set -euo pipefail
[[ $# -eq 2 ]] || {
    printf 'Usage: bash scripts/coverage-summary.sh <llvm-cov export -summary-only json> <repository root with a trailing slash>\nPrints a Markdown table of line and function coverage, lowest line coverage first. Fails when the export lists no file, or a file outside Sources.\n' >&2
    exit 64
}

jq -r --arg root "$2" '
    def pct: (.percent * 10 | round) / 10 | tostring + "%";
    def row($name): "| \($name) | \(.lines | pct) (\(.lines.covered)/\(.lines.count)) | \(.functions | pct) |";
    .data[0] as $data
    | if ($data.files | length) == 0 then error("the coverage export lists no source files") else . end
    | ([$data.files[].filename | select(startswith($root + "Sources/") | not)] | first) as $stray
    | if $stray then error("the coverage export lists a file outside Sources: \($stray)") else . end
    | "## Unit test coverage", "",
      "| File | Lines | Functions |", "| --- | ---: | ---: |",
      ($data.totals | row("**Total**")),
      ($data.files | sort_by(.summary.lines.percent, .filename)[] | .summary as $s | .filename | ltrimstr($root) as $name | $s | row("`\($name)`"))
' "$1"
