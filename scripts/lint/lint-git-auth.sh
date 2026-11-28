#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# -eq 0 ]] || {
    printf 'Usage: lint-git-auth.sh\nFails on each workflow that runs scripts/git-auth.sh with a job token that can do more than read the repo.\n' >&2
    exit 64
}

listed="$(git ls-files -z -- .github/workflows | tr '\0' '\n')" || { echo "lint-git-auth: git ls-files failed" >&2; exit 2; }
failed=0
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    grep -qF 'scripts/git-auth.sh' "$file" || continue
    awk -v file="$file" '
    function fail(line, text) { printf "%s:%d: %s\n", file, line, text; bad = 1 }
    /^[ \t]*#/ { next }
    /^[^ \t]/ { triggers = /^"?on"?:/ }
    triggers && /(^|[^A-Za-z_])(pull_request_target|workflow_run)([^A-Za-z_]|$)/ {
        fail(FNR, "a workflow that runs scripts/git-auth.sh cannot run on pull_request_target or workflow_run.")
    }
    /^permissions:/ {
        top = FNR; block = 1
        if ($0 !~ /^permissions:[ \t]*$/) fail(FNR, "the top permissions must be a block that holds only contents: read.")
        next
    }
    block && /^[^ \t]/ { block = 0 }
    block && /[^ \t]/ {
        if ($0 !~ /^  contents: read[ \t]*$/) fail(FNR, "the top permissions must hold only contents: read.")
        else reads = 1
        next
    }
    /^[ \t]+permissions:/ { fail(FNR, "a workflow that runs scripts/git-auth.sh cannot set permissions on a job.") }
    END {
        if (!top) fail(1, "a workflow that runs scripts/git-auth.sh needs top permissions of contents: read.")
        else if (!reads) fail(top, "the top permissions must hold contents: read.")
        exit bad
    }' "$file" >&2 || failed=1
done <<<"$listed"
if [[ $failed -ne 0 ]]; then
    printf 'lint-git-auth: scripts/git-auth.sh puts the job token in the env of every later step, so it runs only where that token can only read the repo.\n' >&2
    exit 1
fi
