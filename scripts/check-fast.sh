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

step "shell syntax" bash scripts/lint/check-syntax.sh scripts/*.sh scripts/*/*.sh .agents/skills/*/scripts/*.sh .githooks/pre-push
step lint-shell bash scripts/lint/lint-shell.sh
step check-lint-shell bash scripts/lint/check-lint-shell.sh
step lint-colors bash scripts/lint/lint-colors.sh
step lint-callbacks bash scripts/lint/lint-callbacks.sh
step check-lint-callbacks bash scripts/lint/check-lint-callbacks.sh
step lint-claims bash scripts/lint/lint-claims.sh
step check-lint-claims bash scripts/lint/check-lint-claims.sh
step check-lint-comments bash scripts/lint/check-lint-comments.sh
[[ "${1:-}" == --no-comment-lint ]] || step lint-comments bash scripts/lint/lint-comments.sh
step check-docs node scripts/lint/check-docs.mjs
step check-lint-docs bash scripts/lint/check-lint-docs.sh
step check-comments node scripts/lint/check-comments.mjs
step check-lint-script-comments bash scripts/lint/check-lint-script-comments.sh
step lint-casts bash scripts/lint/lint-casts.sh
step check-lint-casts bash scripts/lint/check-lint-casts.sh
step lint-paths bash scripts/lint/lint-paths.sh
step check-lint-paths bash scripts/lint/check-lint-paths.sh
step check-lint-commits bash scripts/lint/check-lint-commits.sh
step check-cleanup-branches bash scripts/check-cleanup-branches.sh
step check-dmg bash scripts/release/check-dmg.sh

if [[ ${#failed[@]} -gt 0 ]]; then
    printf 'check-fast: failed: %s\n' "$(IFS=,; echo "${failed[*]}" | sed 's/,/, /g')" >&2
    exit 1
fi
echo "check-fast: ok"
