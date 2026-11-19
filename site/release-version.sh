#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tag=$(curl -sS -o /dev/null -w '%{redirect_url}' --max-time 30 https://github.com/mauriciopolvora/ciel/releases/latest)
version=${tag##*/v}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'The latest release redirects to %s, which names no vx.y.z tag.\n' "${tag:-nothing}" >&2; exit 1
fi
sed -i.bak -E "s/(\"softwareVersion\": \")[^\"]*\"/\1$version\"/" public/index.html
rm public/index.html.bak
grep -q "\"softwareVersion\": \"$version\"" public/index.html || { printf 'public/index.html has no softwareVersion.\n' >&2; exit 1; }
printf 'softwareVersion %s\n' "$version"
