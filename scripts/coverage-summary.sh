#!/bin/bash
set -euo pipefail
[[ $# -eq 2 ]] || {
    printf 'Usage: bash scripts/coverage-summary.sh <llvm-cov export -summary-only json> <path prefix to drop>\nPrints a Markdown table of line and function coverage, lowest line coverage first.\n' >&2
    exit 64
}

jq -r --arg root "$2" '
    def pct: (.percent * 10 | round) / 10 | tostring + "%";
    def row($name): "| \($name) | \(.lines | pct) (\(.lines.covered)/\(.lines.count)) | \(.functions | pct) |";
    .data[0] as $data
    | "## Unit test coverage", "",
      "| File | Lines | Functions |", "| --- | ---: | ---: |",
      ($data.totals | row("**Total**")),
      ($data.files | sort_by(.summary.lines.percent, .filename)[] | .summary as $s | .filename | ltrimstr($root) as $name | $s | row("`\($name)`"))
' "$1"
