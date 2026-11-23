#!/bin/bash
# Usage: check-fast.sh [--no-comment-lint]. The checks that run without macOS: check.sh runs them first. The pre-push
# hook runs them with --no-comment-lint, then lints the comments in each pushed ref tip.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
"" | --no-comment-lint) ;;
*) printf 'Usage: check-fast.sh [--no-comment-lint]\n' >&2; exit 64 ;;
esac
bash scripts/check-syntax.sh scripts/*.sh .agents/skills/*/scripts/*.sh .githooks/pre-push
bash scripts/lint-shell.sh
bash scripts/check-lint-shell.sh
bash scripts/lint-colors.sh
bash scripts/lint-callbacks.sh
bash scripts/check-lint-callbacks.sh
bash scripts/lint-claims.sh
bash scripts/check-lint-claims.sh
bash scripts/check-lint-comments.sh
[[ "${1:-}" == --no-comment-lint ]] || bash scripts/lint-comments.sh
