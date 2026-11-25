#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# -eq 0 ]] || {
    printf 'Usage: bash scripts/lint/dead-code.sh\nBuilds the package and fails on each declaration that nothing uses, with the settings in .periphery.yml. Set PERIPHERY to the periphery binary when it is not on the PATH.\n' >&2
    exit 64
}

"${PERIPHERY:-periphery}" scan --config .periphery.yml
