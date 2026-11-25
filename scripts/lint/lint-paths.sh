#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 0 ]] || {
    printf 'Usage: lint-paths.sh\nFails on each scripts/ or .agents/skills/<name>/scripts/ path that git does not track.\n' >&2
    exit 64
}

listed="$(git ls-files -z -- .github/workflows .githooks scripts .agents/skills AGENTS.md README.md CONTRIBUTING.md docs |
    tr '\0' '\n')" || { echo "lint-paths: git ls-files failed" >&2; exit 2; }
files=()
while IFS= read -r file; do
    case "$file" in
        "" | scripts/check-lint-*.sh) continue ;;
    esac
    [[ -f "$file" && ! -L "$file" ]] && files+=("$file")
done <<<"$listed"
[[ ${#files[@]} -gt 0 ]] || { echo "lint-paths: found no files to scan" >&2; exit 2; }

found="$(grep -onIE '(^|[^A-Za-z0-9_./$-])(\./)?(\.agents/skills/[A-Za-z0-9_-]+/)?scripts/[A-Za-z0-9_./*-]*' "${files[@]}" /dev/null |
    awk '{
        colon = index($0, ":"); file = substr($0, 1, colon - 1); rest = substr($0, colon + 1)
        colon = index(rest, ":"); line = substr(rest, 1, colon - 1); path = substr(rest, colon + 1)
        if (path !~ /^(\.agents|scripts|\.\/)/) path = substr(path, 2)
        sub(/^\.\//, "", path)
        sub(/\.+$/, "", path)
        root = ""
        if (file ~ /^\.agents\/skills\/[^\/]+\//) { root = file; sub(/^\.agents\/skills\//, "", root); sub(/\/.*/, "", root); root = ".agents/skills/" root "/" }
        print root "|" path "|" file ":" line
    }')" || { status=$?; [[ $status -eq 1 ]] && exit 0; echo "lint-paths: grep failed" >&2; exit 2; }

tracked() { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }
missing=
checked=$'\n'
bad=$'\n'
while IFS="|" read -r root path where; do
    key="$root$path"
    if [[ "$checked" != *$'\n'"$key"$'\n'* ]]; then
        checked+="$key"$'\n'
        tracked "$path" || tracked "$root$path" || bad+="$key"$'\n'
    fi
    [[ "$bad" == *$'\n'"$key"$'\n'* ]] && missing+="    $where: $path"$'\n'
done <<<"$found"
if [[ -n "$missing" ]]; then
    printf 'lint-paths: these paths name no tracked file:\n%sFix the path, or add the file.\n' "$missing" >&2
    exit 1
fi
