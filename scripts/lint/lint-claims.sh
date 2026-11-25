#!/bin/bash
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
ledger=scripts/claims.txt snapshot=scripts/claims-facts.txt known='network arch fullscreen spaces audio'
fail() { printf 'lint-claims: %s\n' "$1" >&2; exit 2; }
lines() { [ -z "$1" ] || printf '%s\n' "$1"; }
probe() {
    local fact=$1 regex=$2 found
    shift 2
    found=$(grep -HE -e "$regex" -- "$@")
    [ $? -le 1 ] || fail "the $fact probe cannot read one of its files."
    lines "$found" | sed -e 's/^\([^:]*\):[[:space:]]*/\1: /' -e 's/[[:space:]]*$//' -e '/^[^:]*: \/\//d' \
        -e '/^[^:]*: #/d' -e 's/[0-9][0-9]*\(\.[0-9][0-9]*\)\{1,\}/*/g' -e "s/^/$fact|/" ||
        fail "sed failed in the $fact probe."
}
facts() {
    local swift=() found file
    found=$(find Sources -name '*.swift') || fail 'cannot read every folder in Sources.'
    while IFS= read -r file; do swift+=("$file"); done < <(lines "$found")
    [ "${#swift[@]}" -gt 0 ] || fail 'found no Swift files in Sources.'
    # WARNING: Sparkle reads each SU key in Info.plist, and its updater properties set what it sends and when.
    probe network 'URLSession|URLRequest|NWConnection|NWPathMonitor|https?://|(^|[^A-Za-z0-9_])SP?U[A-Z]|\.updater\.|sendsSystemProfile|updateCheckInterval|\.download\(|import (Network|Sparkle|WebKit)' \
        "${swift[@]}" Package.swift Resources/Info.plist scripts/appcast.sh
    probe arch 'arm64|x86_64|universal|lipo|-thin|--arch|ARCH' \
        scripts/build.sh scripts/release.sh Package.swift .github/workflows/*.yml
    probe fullscreen '[Ff]ull[Ss]creen([^A]|$)' "${swift[@]}"
    probe spaces 'SLS[A-Z]|CGS[A-Za-z]*Space|[Ss]pace(ID|Id|s?For)|[Aa]ctiveSpace' "${swift[@]}"
    probe audio 'AVAudioFile|AVAudioRecorder|ExtAudioFile|AudioFileCreate|installTap|OffMainCallbacks\.tap|FileHandle|FileManager|createFile|\.write\(|fopen|fwrite|UserDefaults' \
        Sources/Ciel/Dictation/Dictation.swift Sources/Ciel/Dictation/TranscribeCppTranscriber.swift Sources/CielCore/LiveTranscript.swift \
        Sources/CielCore/Speech.swift Sources/Ciel/App/OffMainCallbacks.swift
    probe audio 'AudioClip|AVAudioPCMBuffer' "${swift[@]}"
}
live=$(facts) || exit 2
live=$(lines "$live" | sort -u) || fail 'sort failed on the facts.'
if [ "${1:-}" = --facts ]; then lines "$live"; exit 0; fi
for file in "$ledger" "$snapshot"; do [ -f "$file" ] && [ -r "$file" ] || fail "cannot read $file."; done
sort -cu "$snapshot" 2>/dev/null || fail "$snapshot is not sorted. Write it with: bash scripts/lint-claims.sh --facts > $snapshot"
claims=$(grep -v -e '^#' -e '^$' "$ledger")
[ $? -le 1 ] || fail "cannot read $ledger."
while IFS='|' read -r fact file quote; do
    case "$fact" in '' | *[!a-z]*) fail "$ledger names an unknown fact '$fact'. Use one of: $known." ;; esac
    case " $known " in *" $fact "*) ;; *) fail "$ledger names an unknown fact '$fact'. Use one of: $known." ;; esac
    [ -n "$quote" ] && [ -f "$file" ] && [ -r "$file" ] || fail "$ledger: cannot read $file, or the line has no quote: $fact|$file|$quote"
done < <(lines "$claims")
changes=$(lines "$live" | comm -3 "$snapshot" -) || fail 'comm failed on the facts.'
status=0
if [ -n "$changes" ]; then
    changes=$(lines "$changes" | awk '{ print (substr($0, 1, 1) == "\t" ? "+ " substr($0, 2) : "- " $0) }') || fail 'awk failed.'
    changed=$(lines "$changes" | sed -e 's/^[-+] //' -e 's/|.*//' | sort -u) || fail 'sed or sort failed on the changes.'
    printf 'lint-claims: a code fact under a public claim changed:\n%s\n\nRead each claim for that fact again and fix the copy if the change made it false:\n' "$changes" >&2
    for fact in $changed; do
        while IFS='|' read -r name file quote; do
            [ "$name" = "$fact" ] || continue
            line=$(grep -nF -- "$quote" "$file")
            [ $? -le 1 ] || fail "cannot read $file."
            printf '  %s %s:%s: %s\n' "$fact" "$file" "${line%%:*}" "$quote" >&2
        done < <(lines "$claims")
    done
    printf 'Then run: bash scripts/lint-claims.sh --facts > %s\n' "$snapshot" >&2
    status=1
fi
while IFS='|' read -r fact file quote; do
    grep -qF -- "$quote" "$file"
    case $? in
        0) ;;
        1) printf 'lint-claims: %s no longer contains "%s" (%s). Read the new copy, then put its words in the %s line or delete the line.\n' "$file" "$quote" "$fact" "$ledger" >&2; status=1 ;;
        *) fail "cannot read $file." ;;
    esac
done < <(lines "$claims")
exit "$status"
