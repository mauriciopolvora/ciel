#!/bin/bash
# The checks that run without macOS: the pre-push hook runs them on Linux, and check.sh runs them first.
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/*.sh .githooks/pre-push
bash scripts/lint-colors.sh
