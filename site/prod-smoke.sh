#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
site=${CIEL_SITE_URL:-https://cielmac.app}
failed=0
get() {
    local want="$1" route="$2" headers code
    headers=$(curl -sS --max-time 20 -o /dev/null -D - "$site$route") || headers="curl failed ($?)"
    code=$(awk 'NR == 1 { print $2 }' <<<"$headers")
    printf '%s %s%s\n' "${code:-$headers}" "$site" "$route"
    [[ "$code" == "$want" ]] || failed=1
    if [[ "$route" == / ]] && ! grep -qi '^x-content-type-options: nosniff' <<<"$headers"; then
        printf '%s/ has no X-Content-Type-Options: nosniff\n' "$site" >&2
        failed=1
    fi
}
get 200 /
get 200 /privacy
get 200 /assets/site.js
get 404 /no-such-page
page=$(mktemp)
trap 'rm -f "$page"' EXIT
if curl -sS --max-time 20 -o "$page" "$site/"; then
    bash check-downloads.sh "$page" "$site/" || failed=1
else
    failed=1
fi
exit "$failed"
