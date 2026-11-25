#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
"" | --no-comment-lint) ;;
*)
    printf 'Usage: check-fast.sh [--no-comment-lint]\nRuns the checks that need no macOS and lists each one that failed. The pre-push hook passes\n--no-comment-lint, then runs the Swift comment lint on each pushed ref tip.\n' >&2
    exit 64
    ;;
esac

failed=()
step() {
    local name="$1"
    shift
    "$@" </dev/null || failed+=("$name")
}

step "shell syntax" bash scripts/check-syntax.sh scripts/*.sh .agents/skills/*/scripts/*.sh .githooks/pre-push
step lint-shell bash scripts/lint-shell.sh
step check-lint-shell bash scripts/check-lint-shell.sh
step lint-colors bash scripts/lint-colors.sh
step lint-callbacks bash scripts/lint-callbacks.sh
step check-lint-callbacks bash scripts/check-lint-callbacks.sh
step lint-claims bash scripts/lint-claims.sh
step check-lint-claims bash scripts/check-lint-claims.sh
step check-lint-comments bash scripts/check-lint-comments.sh
[[ "${1:-}" == --no-comment-lint ]] || step lint-comments bash scripts/lint-comments.sh
step check-docs node scripts/check-docs.mjs
step check-lint-docs bash scripts/check-lint-docs.sh
step check-comments node scripts/check-comments.mjs
step check-lint-script-comments bash scripts/check-lint-script-comments.sh
step lint-casts bash scripts/lint-casts.sh
step check-lint-casts bash scripts/check-lint-casts.sh
step lint-paths bash scripts/lint-paths.sh
step check-lint-paths bash scripts/check-lint-paths.sh
step check-lint-commits bash scripts/check-lint-commits.sh

if [[ ${#failed[@]} -gt 0 ]]; then
    printf 'check-fast: failed: %s\n' "$(IFS=,; echo "${failed[*]}" | sed 's/,/, /g')" >&2
    exit 1
fi
echo "check-fast: ok"
