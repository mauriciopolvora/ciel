#!/bin/bash
# Checks the shell syntax of each file it gets. This is the only place that runs bash -n, because bash -n checks only its first file.
set -euo pipefail
[[ $# -gt 0 ]] || { echo "check-syntax.sh: no files to check" >&2; exit 2; }
for file in "$@"; do
    bash -n -- "$file"
done
