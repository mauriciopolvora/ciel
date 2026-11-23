#!/bin/bash
# The checks that run without macOS: the pre-push hook runs them on Linux, and check.sh runs them first.
set -euo pipefail
cd "$(dirname "$0")/.."
# bash -n reads only its first file, so check each one.
for script in scripts/*.sh .githooks/pre-push; do bash -n "$script"; done
bash scripts/lint-colors.sh
