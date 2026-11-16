#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sign_update=.build/artifacts/sparkle/Sparkle/bin/sign_update
# macOS ships LibreSSL, which cannot create Ed25519 keys.
openssl="$(brew --prefix openssl@3)/bin/openssl"
work="$(mktemp -d "$PWD/.build/appcast-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fail() { printf 'Appcast check: %s\n' "$1" >&2; exit 1; }
# A throwaway key made the same way as the release key: its 32 byte Ed25519 seed, which sign_update reads.
umask 077
"$openssl" genpkey -algorithm ed25519 -outform DER -out "$work/key.der"
printf 'SPARKLE_PRIVATE_ED_KEY=%s\n' "$(tail -c 32 "$work/key.der" | base64)" >"$work/key.env"
"$openssl" pkey -inform DER -in "$work/key.der" -pubout -out "$work/public.pem"
plist=Resources/Info.plist
cp "$plist" "$work/Info.plist"
plutil -replace SUPublicEDKey -string "$("$openssl" pkey -pubin -in "$work/public.pem" -outform DER | tail -c 32 | base64)" \
    "$work/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
archive="$work/Ciel-$version-arm64.zip"
ditto -c -k --keepParent Resources "$archive"
bash scripts/appcast.sh "$work/Info.plist" "$archive" "$work/key.env" "$work/appcast.xml"
if bash scripts/appcast.sh "$plist" "$archive" "$work/key.env" "$work/wrong-key.xml" 2>"$work/wrong-key.err"; then
    fail 'a key that does not match SUPublicEDKey in Resources/Info.plist still wrote an appcast.'
fi
grep -q 'does not match SUPublicEDKey' "$work/wrong-key.err" || fail 'a wrong key failed without saying so.'
printf 'PASS appcast.sh refuses a key that does not match SUPublicEDKey: %s\n' "$(cat "$work/wrong-key.err")"
sentinel=ciel-sentinel-malformed-key
printf 'SPARKLE_PRIVATE_ED_KEY=%s\n' "$sentinel" >"$work/sentinel.env"
signer_output="$(printf '%s\n' "$sentinel" | "$sign_update" -p --ed-key-file - "$archive" || true)"
[[ "$signer_output" == *"$sentinel"* ]] ||
    fail 'sign_update no longer prints a malformed key, so the tracing case below proves nothing.'
if bash -x scripts/appcast.sh "$work/Info.plist" "$archive" "$work/sentinel.env" "$work/sentinel.xml" \
    >"$work/sentinel.out" 2>"$work/sentinel.err"; then
    fail 'a malformed key still wrote an appcast.'
fi
if grep -qF "$sentinel" "$work/sentinel.out" "$work/sentinel.err"; then
    fail 'appcast.sh printed the signing key under bash -x.'
fi
grep -q 'sign_update could not sign' "$work/sentinel.err" || fail 'a malformed key failed without saying so.'
printf 'PASS appcast.sh under bash -x keeps a malformed key out of its output: %s\n' \
    "$(grep 'sign_update could not sign' "$work/sentinel.err")"
xmllint --noout "$work/appcast.xml"
field() { xmllint --xpath "string(//item/$1)" "$work/appcast.xml"; }
[[ "$(field '*[local-name()="version"]')" == "$(plutil -extract CFBundleVersion raw "$plist")" ]] ||
    fail 'sparkle:version is not CFBundleVersion.'
[[ "$(field '*[local-name()="shortVersionString"]')" == "$version" ]] ||
    fail 'sparkle:shortVersionString is not CFBundleShortVersionString.'
[[ "$(field '*[local-name()="minimumSystemVersion"]')" == 14.0 ]] || fail 'sparkle:minimumSystemVersion is not 14.0.'
[[ "$(field 'enclosure/@url')" == "https://github.com/mauriciopolvora/ciel/releases/download/v$version/Ciel-$version-arm64.zip" ]] ||
    fail 'the enclosure url is not the versioned release asset.'
[[ "$(field 'enclosure/@length')" == "$(wc -c <"$archive" | tr -d ' ')" ]] || fail 'the enclosure length is not the archive size.'
signature="$(field 'enclosure/@*[local-name()="edSignature"]')"
sed -n 's/^SPARKLE_PRIVATE_ED_KEY=//p' "$work/key.env" |
    "$sign_update" --verify --ed-key-file - "$archive" "$signature" >/dev/null ||
    fail 'sign_update --verify rejected the signature.'
base64 -d <<<"$signature" >"$work/signature.bin"
"$openssl" pkeyutl -verify -pubin -inkey "$work/public.pem" -rawin -in "$archive" -sigfile "$work/signature.bin" >/dev/null ||
    fail 'the signature does not match the public key.'
printf x >>"$archive"
if "$openssl" pkeyutl -verify -pubin -inkey "$work/public.pem" -rawin -in "$archive" -sigfile "$work/signature.bin" >/dev/null 2>&1; then
    fail 'a changed archive still verified.'
fi
printf 'PASS appcast for Ciel %s: valid XML, version, length, minimum system and an EdDSA signature that verifies\n' "$version"
