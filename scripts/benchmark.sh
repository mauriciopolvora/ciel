#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
run_args=(-c release)
if [[ -n "${CIEL_SCRATCH_PATH:-}" ]]; then
    run_args+=(--scratch-path "$CIEL_SCRATCH_PATH")
fi
swift run "${run_args[@]}" CielBenchmarks \
    --budget-ms-per-1000 "${CIEL_BENCHMARK_P95_MS_PER_1000:-100}" \
    --output "${CIEL_BENCHMARK_OUTPUT:-$PWD/.build/performance/search-engine.json}" "$@"
