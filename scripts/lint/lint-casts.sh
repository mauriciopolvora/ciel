#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# -eq 0 ]] || { printf 'Usage: lint-casts.sh\nFails on each as! in a tracked Swift file under Sources, Tests or scripts.\n' >&2; exit 64; }

listed="$(git ls-files -z -- 'Sources/*.swift' 'Tests/*.swift' 'scripts/*.swift' | tr '\0' '\n')" ||
    { echo "lint-casts: git ls-files failed" >&2; exit 2; }
files=()
while IFS= read -r file; do
    [[ -n "$file" && -e "$file" ]] && files+=("$file")
done <<<"$listed"
[[ ${#files[@]} -gt 0 ]] || { echo "lint-casts: found no Swift files under Sources, Tests or scripts" >&2; exit 2; }
for file in "${files[@]}"; do
    [[ -r "$file" ]] || { echo "lint-casts: cannot read $file" >&2; exit 2; }
done

awk '
    FNR == 1 { name = FILENAME; sub(/.*\//, "", name); limit[FILENAME] = (name == "WindowAccessibility.swift") ? 4 : 0 }
    {
        rest = $0
        while (match(rest, /(^|[^A-Za-z0-9_])as!/)) {
            count[FILENAME]++
            where[FILENAME] = where[FILENAME] "\n    " FILENAME ":" FNR ": " $0
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    END {
        for (file in count) {
            if (count[file] <= limit[file]) continue
            print "lint-casts: " file " has " count[file] " as! casts, and it may have " limit[file] "." where[file] > "/dev/stderr"
            failed = 1
        }
        if (failed) print "lint-casts: use as? with guard let or if let. Only a file named WindowAccessibility.swift may hold up to 4, for the CoreFoundation casts where as? always succeeds." > "/dev/stderr"
        exit failed
    }
' "${files[@]}"
