#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

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
)

mutate() {
    case "$1" in
        M1) swap Sources/CielCore/LauncherPlacement.swift 's/\bhorizontal\b/horizontalFraction/g' ;;
        M2) swap Sources/CielCore/WindowAction.swift 's/case maximize, /case maximize = "maximise"\n    case /' ;;
        M3)
            swap Sources/Ciel/HotKeys.swift 's/let keyCode: UInt32/let code: UInt32/' &&
                swap Sources/Ciel/HotKeys.swift 's/keyName\(keyCode\)/keyName(code)/' &&
                swap Sources/Ciel/HotKeys.swift 's/Shortcut\(keyCode:/Shortcut(code:/g' &&
                swap Sources/Ciel/HotKeys.swift 's/shortcut\.keyCode/shortcut.code/g'
            ;;
        M4)
            swap Sources/CielCore/WindowAction.swift 's/bottomRight, minimize\n/bottomRight, minimize, leftThird\n/' &&
                swap Sources/CielCore/WindowAction.swift \
                    's/(case \.minimize: return "Minimize"\n)/$1        case .leftThird: return "Left Third"\n/'
            ;;
        M5) swap Sources/CielCore/Search.swift 's/id: "settings"/id: "preferences"/' ;;
        M6)
            swap Sources/Ciel/LauncherView.swift \
                's/(insertTab\(_:\)\):\n\s+selectFilter\()filter == nil \? 1 : filter == \.application \? 2 : 0/${1}filter == nil ? 2 : filter == .application ? 0 : 1/' &&
                swap Sources/Ciel/LauncherView.swift \
                    's/(insertBacktab\(_:\)\):\n\s+selectFilter\()filter == nil \? 2 : filter == \.application \? 0 : 1/${1}filter == nil ? 1 : filter == .application ? 2 : 0/'
            ;;
        M7) swap Sources/Ciel/WindowOperationEngine.swift 's/(window position\."\s*\}\n\s+return )action\.title/$1"Done"/' ;;
        M8) swap Sources/Ciel/AppIdentity.swift 's/"app\.mauriciopolvora\.ciel"/"app.mauriciopolvora.ciel-app"/' ;;
        M9)
            swap Sources/Ciel/Diagnostics/LaunchMode.swift \
                's/\n\s+guard bundleIdentifier == AppIdentity\.checksBundleIdentifier else \{\n[^\n]*\n\s+\}//'
            ;;
        M10) swap Sources/Ciel/Diagnostics/LaunchMode.swift 's/default: return nil/default: self = .app/' ;;
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
for entry in "${mutants[@]}"; do
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
