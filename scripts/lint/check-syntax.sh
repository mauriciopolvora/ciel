#!/bin/bash
# WARNING: bash -n checks only its first file, so this runs it once per file.
set -euo pipefail
[[ $# -gt 0 ]] || { echo "check-syntax.sh: no files to check" >&2; exit 2; }
for file in "$@"; do
    bash -n -- "$file"
done
