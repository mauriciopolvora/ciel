#!/bin/bash
set -euo pipefail
if [[ $# -ne 4 ]]; then
    printf 'Usage: bash scripts/appcast.sh <Info.plist> <archive.zip> <key file> <appcast.xml>\n' >&2; exit 1
fi
plist="$1" archive="$2" key_file="$3" appcast="$4"
sign_update="$(dirname "$0")/../.build/artifacts/sparkle/Sparkle/bin/sign_update"
version="$(plutil -extract CFBundleVersion raw "$plist")"
short_version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
minimum_system="$(plutil -extract LSMinimumSystemVersion raw "$plist")"
# WARNING: on a malformed key sign_update prints the key, so tracing stays off until the signature is well formed.
tracing="${-//[^x]/}"
{ set +x; } 2>/dev/null
signature="$(sed -n 's/^SPARKLE_PRIVATE_ED_KEY=//p' "$key_file" | "$sign_update" -p --ed-key-file - "$archive" 2>/dev/null)" ||
    signature=''
[[ "$signature" =~ ^[A-Za-z0-9+/]{86}==$ ]] || signature=''
if [[ -n "$tracing" ]]; then set -x; fi
if [[ -z "$signature" ]]; then
    printf 'sign_update could not sign %s with the key in %s.\n' "$archive" "$key_file" >&2; exit 1
fi
if ! swift "$(dirname "$0")/VerifyUpdate.swift" "$(plutil -extract SUPublicEDKey raw "$plist")" "$signature" "$archive"; then
    printf 'The key in %s does not match SUPublicEDKey in %s, so installed copies would reject this update.\n' \
        "$key_file" "$plist" >&2; exit 1
fi
cat >"$appcast" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Ciel</title>
        <item>
            <title>Ciel $short_version</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$version</sparkle:version>
            <sparkle:shortVersionString>$short_version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/mauriciopolvora/ciel/releases/download/v$short_version/$(basename "$archive")" length="$(wc -c <"$archive" | tr -d ' ')" type="application/octet-stream" sparkle:edSignature="$signature"/>
        </item>
    </channel>
</rss>
EOF
