#!/bin/bash
# The checks that run without macOS: the pre-push hook runs them on Linux, and check.sh runs them first.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-syntax.sh scripts/*.sh .agents/skills/*/scripts/*.sh .githooks/pre-push
bash scripts/lint-shell.sh
bash scripts/check-lint-shell.sh
bash scripts/lint-colors.sh
bash scripts/lint-callbacks.sh
bash scripts/check-lint-callbacks.sh
