#!/bin/bash
# Fails on each bash -n, sh -n or -o noexec call outside scripts/check-syntax.sh, because bash -n checks only its first file.
# Usage: lint-shell.sh [file...]. With no files it reads every tracked shell script, hook and workflow.
set -euo pipefail
caller="$PWD"
cd "$(dirname "$0")/.."

files=()
if [[ $# -gt 0 ]]; then
    for file in "$@"; do
        case "$file" in
            /*) files+=("$file") ;;
            *) files+=("$caller/$file") ;;
        esac
    done
else
    # -z prints each name as it is. Without it, git quotes a name that holds " or \ even with core.quotePath=false.
    listed="$(git ls-files -z -- '*.sh' '*.yml' '*.yaml' '.githooks/*' | tr '\0' '\n')" || { echo "lint-shell.sh: git ls-files failed" >&2; exit 2; }
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("./$file")
    done <<< "$listed"
fi
checked=()
for file in ${files[@]+"${files[@]}"}; do
    [[ -f "$file" && -r "$file" ]] || { echo "lint-shell.sh: cannot read $file" >&2; exit 2; }
    [[ "$file" -ef scripts/check-syntax.sh || "$file" -ef scripts/lint-shell.sh || "$file" -ef scripts/check-lint-shell.sh ]] || checked+=("$file")
done
[[ ${#checked[@]} -gt 0 ]] || exit 0

awk '
/^[ \t]*#/ { next }
/(^|[^A-Za-z0-9_.-])((ba)?sh|BASH)([^A-Za-z0-9_.-].*)?[^A-Za-z0-9_-](-[A-Za-z]*n[A-Za-z]*|noexec)([^A-Za-z0-9_-]|$)/ {
    printf "%s:%d: Check shell syntax with bash scripts/check-syntax.sh <file>..., not bash -n, sh -n or -o noexec. bash -n checks only its first file.\n", FILENAME, FNR
    failed = 1
}
END { exit failed }
' "${checked[@]}"
