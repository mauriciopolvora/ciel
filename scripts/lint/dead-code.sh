#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# -eq 0 ]] || {
    printf 'Usage: bash scripts/lint/dead-code.sh\nBuilds the package and fails on each declaration that nothing uses. Set PERIPHERY to the periphery binary when it is not on the PATH.\n' >&2
    exit 64
}

"${PERIPHERY:-periphery}" scan --strict --relative-results --disable-update-check
