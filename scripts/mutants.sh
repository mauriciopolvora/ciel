#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
shard=1
shards=1
if [[ $# -eq 2 && "$1" == --shard && "$2" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] && ((BASH_REMATCH[1] <= BASH_REMATCH[2])); then
    shard=${BASH_REMATCH[1]}
    shards=${BASH_REMATCH[2]}
elif [[ $# -ne 0 ]]; then
    printf 'Usage: bash scripts/mutants.sh [--shard <n>/<total>]\nWith --shard, runs every mutant whose 0-based index modulo <total> is <n> - 1.\n' >&2
    exit 64
fi

mutants=(
    "M1|Rename a LauncherPlacement field"
    "M2|Change a WindowAction raw value"
    "M3|Rename Shortcut.keyCode"
    "M4|Add a WindowAction case with only a title"
    "M5|Rename the settings utility id"
    "M6|Reverse the Tab category cycle"
    "M7|Change the window engine success value"
    "M8|Change AppIdentity without Info.plist"
    "M9|Run a native check under any bundle identifier"
    "M10|Launch the app on an unknown flag"
    "M11|Match FSEvents paths against uncanonicalized catalog roots"
    "M12|Bind window hotkeys under a renamed key"
    "M13|Save a shortcut that was never registered"
    "M14|Let a window command target Ciel itself"
    "M15|Read an unset toggle as off"
    "M16|Yield to a visibility correction before the window responds"
    "M17|Wait 0.25 s before retrying an unchanged window"
    "M18|Retry from the original frame instead of the last observed one"
    "M19|Shrink the frame tolerance to 2 points"
    "M20|Settle as constrained when the frame changed after the retry"
    "M21|Deliver an icon load that was invalidated and requested again"
    "M22|Let an invalidated icon load keep its in-flight slot"
    "M23|Accept a speech model download without checking its SHA-256"
    "M24|Save a launcher shortcut that Spotlight still holds"
    "M25|Read a Spotlight shortcut missing from the saved list as off"
    "M26|Save a launcher shortcut from Settings that Spotlight still holds"
    "M27|Report a downloading speech model as not downloaded"
    "M28|Drop the default dictation key while it waits for access"
    "M29|Refuse a full screen window instead of taking it out of full screen"
    "M30|Let the selected row style recolor result icons"
    "M31|Open Keyboard settings without the Spotlight anchor"
    "M32|Never show the Spotlight card under System Settings"
    "M33|Match a pick only when its query equals the typed query"
    "M34|Count a test wait's budget in wall time instead of in its own polls"
)

mutate() {
    case "$1" in
        M1) swap Sources/CielCore/LauncherPlacement.swift 's/\bhorizontal\b/horizontalFraction/g' ;;
        M2) swap Sources/CielCore/WindowAction.swift 's/case maximize, /case maximize = "maximise"\n    case /' ;;
        M3)
            swap Sources/Ciel/Shortcuts/HotKeys.swift 's/let keyCode: UInt32/let code: UInt32/' &&
                swap Sources/Ciel/Shortcuts/HotKeys.swift 's/keyName\(keyCode\)/keyName(code)/' &&
                swap Sources/Ciel/Shortcuts/HotKeys.swift 's/rawValue: keyCode\)/rawValue: code)/' &&
                swap Sources/Ciel/Shortcuts/HotKeys.swift 's/Shortcut\(keyCode:/Shortcut(code:/g' &&
                swap Sources/Ciel/Shortcuts/HotKeys.swift 's/shortcut\.keyCode/shortcut.code/g'
            ;;
        M4)
            swap Sources/CielCore/WindowAction.swift 's/bottomRight, minimize\n/bottomRight, minimize, leftThird\n/' &&
                swap Sources/CielCore/WindowAction.swift \
                    's/(case \.minimize: return "Minimize"\n)/$1        case .leftThird: return "Left Third"\n/'
            ;;
        M5) swap Sources/CielCore/Search.swift 's/case settings, rescan/case settings = "preferences", rescan/' ;;
        M6)
            swap Sources/Ciel/Launcher/LauncherView.swift \
                's/(insertTab\(_:\)\):\n\s+selectFilter\()filter == nil \? 1 : filter == \.application \? 2 : 0/${1}filter == nil ? 2 : filter == .application ? 0 : 1/' &&
                swap Sources/Ciel/Launcher/LauncherView.swift \
                    's/(insertBacktab\(_:\)\):\n\s+selectFilter\()filter == nil \? 2 : filter == \.application \? 0 : 1/${1}filter == nil ? 1 : filter == .application ? 2 : 0/'
            ;;
        M7) swap Sources/Ciel/Windows/WindowOperationEngine.swift 's/(\.positionLimited\s*\}\n\s+return )\.applied/$1.sizeLimited/' ;;
        M8) swap Sources/Ciel/App/AppIdentity.swift 's/"app\.mauriciopolvora\.ciel"/"app.mauriciopolvora.ciel-app"/' ;;
        M9)
            swap Sources/Ciel/Diagnostics/LaunchMode.swift \
                's/\n\s+guard bundleIdentifier == AppIdentity\.checksBundleIdentifier else \{\n[^\n]*\n\s+\}//'
            ;;
        M10) swap Sources/Ciel/Diagnostics/LaunchMode.swift 's/default: return nil/default: self = .app/' ;;
        M11)
            swap Sources/Ciel/Launcher/AppCatalog.swift \
                's/canonicalRoots = roots\.map \{ CatalogPaths\.canonical\(\$0\.path\) \}/canonicalRoots = roots.map(\\.path)/g'
            ;;
        M12) swap Sources/Ciel/Shortcuts/HotKeys.swift 's/case \.window\(let action\): action\.id/case .window(let action): "win." + action.rawValue/' ;;
        M13)
            swap Sources/Ciel/Shortcuts/HotKeys.swift \
                's/(registrations\[command\] != nil \{ return \}\n)\s+try register\(command, shortcut\)\n/$1/'
            ;;
        M14)
            swap Sources/Ciel/Windows/WindowController.swift \
                's/guard let pid, pid != ProcessInfo\.processInfo\.processIdentifier else/guard let pid else/'
            ;;
        M15) swap Sources/Ciel/App/Preferences.swift 's/defaults\.object\(forKey: key\) == nil \|\| //' ;;
        M16) swap Sources/CielCore/FrameSettle.swift 's/needsVisibilityCorrection, !isUnchanged, /needsVisibilityCorrection, /' ;;
        M17) swap Sources/CielCore/FrameSettle.swift 's/(unchangedRetryDelay: TimeInterval = )0\.2\n/${1}0.25\n/' ;;
        M18) swap Sources/Ciel/Windows/WindowOperationEngine.swift 's/try update\(window, from: settle\.last,/try update(window, from: original,/' ;;
        M19) swap Sources/CielCore/FrameSettle.swift 's/tolerance: CGFloat = 3/tolerance: CGFloat = 2/' ;;
        M20) swap Sources/CielCore/FrameSettle.swift 's/\n\s+guard Self\.matches\(last, retryFrame\) else \{ return \.keepPolling \}//' ;;
        M21) swap Sources/Ciel/Launcher/IconCache.swift 's/guard loads\[path\] === load else/guard loads[path] != nil else/' ;;
        M22)
            swap Sources/Ciel/Launcher/IconCache.swift \
                's/\n(\s+)loadsInFlight -= 1\n(\s+defer \{ startQueuedLoads\(\) \}\n\s+guard loads\[path\] === load else \{ return \}\n)/\n$2$1loadsInFlight -= 1\n/'
            ;;
        M23) swap Sources/Ciel/Dictation/SpeechModelStore.swift 's/guard digest == model\.sha256 else/guard !digest.isEmpty else/' ;;
        M24) swap Sources/Ciel/Onboarding/SpotlightGuide.swift 's/if spotlight\.owns\(shortcut\) \{/if false {/' ;;
        M25)
            swap Sources/Ciel/Shortcuts/SpotlightShortcuts.swift \
                's/guard let entry = saved\[id\] as\? \[String: Any\] else \{ return shipped \}/guard let entry = saved[id] as? [String: Any] else { return nil }/'
            ;;
        M26)
            swap Sources/Ciel/Settings/SettingsController.swift \
                's/\n\s+launcher\.onRecord = \{ \[weak self\] shortcut in self\?\.spotlightGuide\.choose\(shortcut\) \}//'
            ;;
        M27)
            swap Sources/Ciel/Dictation/Dictation.swift \
                's/case \.downloading\(let fraction\): return \.downloading\(percent: Int\(fraction \* 100\)\)/case .downloading: return .notReady/'
            ;;
        M28)
            swap Sources/Ciel/Shortcuts/HotKeys.swift \
                's/do \{ try register\(command, shortcut\) \} catch HotKeyError\.needsAccess \{\}/try register(command, shortcut)/'
            ;;
        M29)
            swap Sources/Ciel/Windows/WindowOperationEngine.swift \
                's/= try leaveFullScreen\(window, check: budget\)\n/= try { () throws -> Bool in if try window.isFullScreen(timeout: budget.timeout()) { throw WindowError.fullScreen }; return false }()\n/'
            ;;
        M30)
            swap Sources/Ciel/Launcher/LauncherResults.swift \
                's/\n\s+override var interiorBackgroundStyle: NSView\.BackgroundStyle \{ \.normal \}//'
            ;;
        M31) swap Sources/Ciel/Shortcuts/SpotlightShortcuts.swift 's/\.extension\?Spotlight"/.extension"/' ;;
        M32) swap Sources/Ciel/Onboarding/SpotlightGuide.swift 's/\n\s+companion\.show\(\)//' ;;
        M33) swap Sources/CielCore/Search.swift 's/where pick\.query\.hasPrefix\(key\)/where pick.query == key/' ;;
        M34)
            swap Tests/CielAppTests/Support/WaitUntil.swift \
                's/for _ in 0\.\.<polls \{\n\s+if condition\(\) \{ return \}\n(\s+try await Task\.sleep\(for: \.milliseconds\(1\)\)\n)\s+\}\n\s+guard condition\(\) else \{ throw WaitTimedOut\(\) \}/let deadline = ContinuousClock.now.advanced(by: .milliseconds(polls))\n    while !condition() {\n        guard ContinuousClock.now < deadline else { throw WaitTimedOut() }\n$1    }/'
            ;;
    esac
}

swap() {
    local file="$work/$1"
    if ! perl -0777 -ne "exit((${2}) ? 0 : 3)" "$file"; then
        printf '%s no longer applies to %s. Update it in scripts/mutants.sh.\n' "$id" "$1" >&2
        return 1
    fi
    perl -0777 -i -pe "$2" "$file"
    touched+=("$1")
}

run_tests() {
    (cd "$work" && bash scripts/test.sh) >"$1" 2>&1
}

work="$(mktemp -d "${TMPDIR:-/tmp}/ciel-mutants.XXXXXX")"
trap 'rm -rf "$work"' EXIT
logs="$root/.build/mutants"
mkdir -p "$logs"
rsync -a --exclude /.build --exclude /dist --exclude /.git "$root/" "$work/"

if ! run_tests "$logs/baseline.log"; then
    printf 'The unmutated suite fails. See %s.\n' "$logs/baseline.log" >&2
    exit 1
fi

failures=0
printf '| Mutant | Mistake | Result |\n| --- | --- | --- |\n'
for index in "${!mutants[@]}"; do
    ((index % shards == shard - 1)) || continue
    entry="${mutants[index]}"
    id="${entry%%|*}"
    touched=()
    if ! mutate "$id"; then
        result="FAILED TO APPLY"
        failures=$((failures + 1))
    elif run_tests "$logs/$id.log"; then
        result="SURVIVED"
        failures=$((failures + 1))
    else
        plain="$(sed $'s/\x1b\\[[0-9;]*m//g' "$logs/$id.log")"
        error="$(grep -m1 -oE '[A-Za-z]+\.swift:[0-9]+:[0-9]+: error: .*' <<<"$plain" || true)"
        failed="$(sed -nE '/^✘ Test run with /d; s/^✘ Test (.*) failed after .*/\1/p' <<<"$plain" | sort -u)"
        if [[ -n "$error" ]]; then
            result="caught: compile fail \`$error\`"
        elif [[ -n "$failed" ]]; then
            result="caught: $(wc -l <<<"$failed" | tr -d ' ') test(s) fail, including \`$(head -1 <<<"$failed")\`"
        else
            result="caught: test run failed, see .build/mutants/$id.log"
        fi
    fi
    for file in ${touched[@]+"${touched[@]}"}; do cp "$root/$file" "$work/$file"; done
    printf '| %s | %s | %s |\n' "$id" "${entry#*|}" "$result"
done

if ((failures > 0)); then
    printf '%d mutant(s) survived or failed to apply. Logs are in .build/mutants.\n' "$failures" >&2
    exit 1
fi
