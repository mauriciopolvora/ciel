#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
listed="$scratch/files"
git ls-files -z | while IFS= read -r -d '' file; do
    if [ -e "$file" ] || [ -L "$file" ]; then printf '%s\0' "$file"; fi
done >"$listed"
tar -cf "$scratch/repo.tar" --null -T "$listed"
edit() {
    sed -e "$1" "$2" >"$2.new" && ! cmp -s "$2" "$2.new" && mv "$2.new" "$2"
}
expect() {
    rm -rf "$scratch/repo" && mkdir "$scratch/repo" && tar -xf "$scratch/repo.tar" -C "$scratch/repo"
    (cd "$scratch/repo" && eval "$4") || { printf 'check-lint-claims: %s: the command that breaks the copy failed.\n' "$1" >&2; exit 1; }
    status=0 && bash "$scratch/repo/scripts/lint-claims.sh" 2>"$scratch/err" || status=$?
    if [ "$status" != "$2" ] || ! { [ -z "$3" ] || grep -qF -- "$3" "$scratch/err"; }; then
        printf 'check-lint-claims: %s: expected exit %s with "%s", got exit %s:\n' "$1" "$2" "$3" "$status" >&2
        cat "$scratch/err" >&2 && exit 1
    fi
}
expect 'the repo as it is' 0 '' ':'
expect 'a new network call' 1 'network README.md:' \
    'printf "let (data, _) = try await URLSession.shared.data(from: url)\n" >>Sources/Ciel/Updater.swift'
expect 'a changed feed URL' 1 'network site/public/privacy.html:' \
    'edit "s#releases/latest/download#releases/download/beta#" Resources/Info.plist'
expect 'a new architecture' 1 'arch README.md:' \
    'printf "lipo \"\$app\" -thin x86_64 -output \"\$app\"\n" >>scripts/build.sh'
expect 'a changed architecture line' 1 'arch site/public/index.html:' \
    'edit "s/-thin arm64/-thin \"\$slice\"/" scripts/build.sh'
expect 'a new full screen line' 1 'fullscreen README.md:' \
    'printf "let fullScreen = false\n" >>Sources/Ciel/WindowOperationEngine.swift'
expect 'a changed full screen line' 1 'fullscreen site/public/index.html:' \
    'edit "s/try window.exitFullScreen(timeout: budget.timeout())/throw WindowError.fullScreen/" Sources/Ciel/WindowOperationEngine.swift'
expect 'a new audio write' 1 'audio README.md:' \
    'printf "try FileHandle(forWritingTo: url).write(contentsOf: data)\n" >>Sources/Ciel/Dictation.swift'
expect 'a changed audio tap' 1 'audio site/public/privacy.html:' \
    'edit "s/bufferSize: [0-9]*/bufferSize: 1/" Sources/Ciel/Dictation.swift'
expect 'a comment' 0 '' 'printf "// URLSession and full screen\n" >>Sources/Ciel/Updater.swift'
expect 'a version bump' 0 '' 'edit "s/exact: \"2\.[0-9.]*\"/exact: \"9.9.9\"/" Package.swift && ! grep -q "exact: \"2\." Package.swift'
expect 'a lost quote' 1 'README.md no longer contains' \
    'grep -vF "It makes two kinds" README.md >"$scratch/readme" && mv "$scratch/readme" README.md'
expect 'a new Sparkle key' 1 'network site/public/privacy.html:' \
    'edit "s#<key>SUEnableAutomaticChecks</key><true/>#&<key>SUSendProfileInfo</key><true/>#" Resources/Info.plist'
expect 'a changed Sparkle setting' 1 'network README.md:' \
    'edit "s#<key>SUEnableAutomaticChecks</key><true/>#<key>SUEnableAutomaticChecks</key><false/>#" Resources/Info.plist'
expect 'a system profile turned on' 1 'network site/public/privacy.html:' \
    'edit "s/controller.updater.automaticallyChecksForUpdates = newValue/&; controller.updater.sendsSystemProfile = true/" Sources/Ciel/Updater.swift'
expect 'a model download on a new path' 1 'network README.md:' \
    'printf "func start(_ speech: SpeechModelStore) { speech.download() }\n" >>Sources/Ciel/SettingsController.swift'
expect 'a Spaces call' 1 'spaces README.md:' \
    'printf "let space = CGSGetActiveSpace(connection)\n" >>Sources/Ciel/WindowOperationEngine.swift'
expect 'samples saved from a new file' 1 'audio site/public/index.html:' \
    'printf "func saveSample(_ clip: AudioClip) {}\n" >Sources/Ciel/AudioDiagnostics.swift'
expect 'two fact names in one ledger line' 2 "unknown fact 'network arch'" \
    'edit "s/^network|README.md|It makes/network arch|README.md|It makes/" scripts/claims.txt'
expect 'a missing ledger' 2 'cannot read scripts/claims.txt' 'rm scripts/claims.txt'
expect 'a missing probed file' 2 'the network probe cannot read' 'rm scripts/appcast.sh'
