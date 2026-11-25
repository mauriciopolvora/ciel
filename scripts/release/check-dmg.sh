#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-dmg.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/Ciel.app"
failures=0
case_number=0

expect() {
    local name="$1" want_status="$2" want_first="$3" stubs output status=0
    shift 3
    case_number=$((case_number + 1))
    stubs="$scratch/stubs-$case_number"
    mkdir "$stubs"
    while [[ $# -gt 0 ]]; do
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            printf '#!/bin/sh\nexit %s\n' "$2" >"$stubs/$1"
        else
            printf '#!/bin/sh\n%s\n' "$2" >"$stubs/$1"
        fi
        chmod +x "$stubs/$1"
        shift 2
    done
    output="$(PATH="$stubs:$PATH" bash scripts/release/dmg.sh "$scratch/Ciel.app" "$scratch/out.dmg" 2>&1)" || status=$?
    if [[ "$status" -ne "$want_status" || ! "$(head -n 1 <<<"$output")" =~ $want_first || -e "$scratch/out.dmg" ]]; then
        printf 'FAIL %s: exit %s, expected %s. dmg.sh output:\n%s\n' "$name" "$status" "$want_status" "$output"
        failures=$((failures + 1))
    fi
}

line_of() { grep -n -m 1 "$1" scripts/release/dmg.sh | cut -d: -f1; }
expect "a failed top level command" 3 '^dmg\.sh:[0-9]+: swift .* exited 3$' swift 3
expect "a failed command inside a function" 4 "^dmg\.sh:$(line_of '^hex() '): .* exited 4\$" swift 0 tiffutil 0 xxd 4
expect "hdiutil create failing on every attempt" 17 '^hdiutil create failed on attempt 1 of 5\. ' \
    swift 0 sleep 0 hdiutil 17 \
    tiffutil 'while [ $# -gt 1 ]; do [ "$1" = -out ] && : >"$2"; shift; done' \
    ditto 'mkdir -p "$2"' \
    plutil 'case $2 in iconSize) echo 128.000000 ;; textSize) echo 13.000000 ;; backgroundType) echo 2 ;; *) echo alias ;; esac' \
    base64 "cat >/dev/null; printf '\\000\\025Ciel:.background.tiff\\000'"

if [[ "$failures" -gt 0 ]]; then
    exit 1
fi
printf 'check-dmg: ok\n'
