#!/bin/bash
set -euo pipefail
page=$(realpath "${1:-$(dirname "$0")/public/index.html}")
cd "$(dirname "$0")"
urls=$(grep -oE 'https://github\.com/mauriciopolvora/ciel/releases/latest/download/[A-Za-z0-9._-]+' "$page" | sort -u)
if [[ -z "$urls" ]]; then
    printf '%s has no release download links.\n' "${2:-$page}" >&2; exit 1
fi
dead=0
while IFS= read -r url; do
    code=$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 120 "$url") || code="$code, and the download failed"
    if [[ "$code" == 200 ]]; then
        printf '200 %s\n' "$url"
    else
        printf 'HTTP %s for %s: the latest release has no %s. Publish a release with it before you deploy the site.\n' \
            "$code" "$url" "${url##*/}" >&2
        dead=1
    fi
done <<<"$urls"
exit "$dead"
