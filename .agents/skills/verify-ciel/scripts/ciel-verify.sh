#!/bin/bash
# Drives a disposable copy of dist/Ciel.app the way a user does. Run it with no arguments for the usage.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
run_dir="${CIEL_VERIFY_DIR:-$repo/.build/verify}"
evidence_root="$run_dir/evidence"
bundle_id=app.mauriciopolvora.ciel.verify
app="$run_dir/CielVerify.app"
binary="$app/Contents/MacOS/Ciel"
pid_file="$run_dir/ciel.pid"
started_file="$run_dir/started-apps"
target_dir="$run_dir/ciel-verify-target"

usage() {
    cat >&2 <<'EOF'
Usage: ciel-verify.sh <command>
  launch [--fresh]        copy dist/Ciel.app as app.mauriciopolvora.ciel.verify and start it.
                          --fresh keeps onboarding; without it the launcher opens at launch.
  doctor                  check that the instance is ours, alive and driveable.
  press <key>             press a key: ctrl+opt+space, escape, return, tab, down, up, cmd+comma.
  close <title>           click the close button of Ciel's window with that title.
  type <text>             type text into the focused field.
  snapshot <name>         write the accessibility tree of Ciel's windows to <name>.ax.txt and print it.
  shot <name>             write a screenshot to <name>.png.
  wait-for <regex> [s]    wait until the accessibility tree matches the extended regex (default 10 s).
  wait-gone <regex> [s]   wait until it no longer matches.
  journey <feature>       launch, doctor, drive one feature, clean up: launcher-search, open-app,
                          window-commands, settings, onboarding, or all.
  cleanup                 stop what this script started. Keeps the evidence.
Evidence goes to .build/verify/evidence/<run id>/, and .build/verify/evidence/latest points at the newest run.
EOF
    exit 64
}

fail() {
    printf 'FAIL %s\n' "$*"
    exit 1
}

evidence_dir() {
    if [[ ! -L "$evidence_root/latest" ]]; then new_evidence_dir; fi
    printf '%s\n' "$evidence_root/$(readlink "$evidence_root/latest")"
}

new_evidence_dir() {
    local id
    id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mkdir -p "$evidence_root/$id"
    ln -sfn "$id" "$evidence_root/latest"
}

ciel_pid() {
    [[ -f "$pid_file" ]] || return 1
    local pid
    pid="$(cat "$pid_file")"
    [[ "$(ps -p "$pid" -o comm= 2>/dev/null)" == "$binary" ]] || return 1
    printf '%s\n' "$pid"
}

other_ciel() {
    ps -axo pid=,comm= | awk -v ours="$binary" '$2 ~ /\/Contents\/MacOS\/Ciel$/ && $2 != ours { print }'
}

launch() {
    local fresh=0
    [[ "${1:-}" == --fresh ]] && fresh=1
    if ciel_pid >/dev/null; then fail "launch: an instance from this script is still running. Run cleanup first."; fi
    if [[ -n "$(other_ciel)" ]]; then
        fail "launch: another Ciel is running and holds the launcher shortcut. Quit it first: $(other_ciel)"
    fi
    [[ -d "$repo/dist/Ciel.app" ]] || fail "launch: dist/Ciel.app is missing. Run bash scripts/build.sh first."
    mkdir -p "$run_dir"
    rm -rf "$app"
    ditto "$repo/dist/Ciel.app" "$app"
    /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
    codesign --force --sign - --preserve-metadata=entitlements,flags "$app" 2>/dev/null
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    defaults write "$bundle_id" SUEnableAutomaticChecks -bool false
    if [[ $fresh -eq 0 ]]; then defaults write "$bundle_id" onboarded -bool true; fi
    new_evidence_dir
    nohup "$binary" >"$(evidence_dir)/ciel.log" 2>&1 &
    printf '%s\n' "$!" >"$pid_file"
    disown
    local ready="Search apps and commands"
    [[ $fresh -eq 1 ]] && ready="Set Up Ciel"
    wait_for "$ready" 15 >/dev/null || fail "launch: Ciel did not show \"$ready\" within 15 s. See $(evidence_dir)/ciel.log."
    printf 'PASS launch pid %s, evidence in %s\n' "$(ciel_pid)" "$(evidence_dir)"
}

ax_tree() {
    local pid
    pid="$(ciel_pid)" || fail "no Ciel instance from this script is running. Run launch first."
    osascript -l JavaScript "$here/ax-tree.js" "$pid"
}

doctor() {
    local pid trusted tree
    pid="$(ciel_pid)" || fail "doctor: no Ciel instance from this script is running."
    printf 'ok   process %s runs %s\n' "$pid" "$binary"
    [[ "$(defaults read "$app/Contents/Info" CFBundleIdentifier)" == "$bundle_id" ]] ||
        fail "doctor: the copy does not run as $bundle_id."
    printf 'ok   bundle id %s, so the installed Ciel keeps its settings\n' "$bundle_id"
    printf 'ok   build %s\n' "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)"
    trusted="$(osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()')"
    [[ "$trusted" == true ]] ||
        fail "doctor: this terminal has no Accessibility access. Grant it in System Settings > Privacy & Security > Accessibility."
    printf 'ok   Accessibility access for the driver and the Ciel it started\n'
    tree="$(ax_tree)" || fail "doctor: System Events cannot read Ciel's windows."
    if grep -q 'Launcher shortcut unavailable' <<<"$tree"; then
        fail "doctor: Ciel could not register the launcher shortcut. Another app holds Control-Option-Space."
    fi
    printf 'ok   Ciel answers System Events and holds the launcher shortcut\n'
}

press() {
    local code mods=""
    case "$1" in
    ctrl+opt+space) code=49 mods=" using {control down, option down}" ;;
    escape) code=53 ;;
    return) code=36 ;;
    tab) code=48 ;;
    down) code=125 ;;
    up) code=126 ;;
    cmd+comma) code=43 mods=" using {command down}" ;;
    *) fail "press: unknown key $1" ;;
    esac
    osascript -e "tell application \"System Events\" to key code $code$mods"
}

close_window() {
    osascript -e 'on run argv' -e 'tell application "System Events" to tell (first process whose unix id is (item 1 of argv as integer))' \
        -e 'click (first button of window (item 2 of argv) whose subrole is "AXCloseButton")' -e 'end tell' -e 'end run' \
        "$(cat "$pid_file")" "$1" >/dev/null
}

type_text() {
    osascript -e 'on run argv' -e 'tell application "System Events" to keystroke (item 1 of argv)' -e 'end run' "$1"
}

snapshot() {
    local file
    file="$(evidence_dir)/$1.ax.txt"
    ax_tree >"$file"
    cat "$file"
}

shot() {
    screencapture -x "$(evidence_dir)/$1.png"
    printf 'wrote %s\n' "$(evidence_dir)/$1.png"
}

wait_for() {
    local deadline=$((SECONDS + ${2:-10}))
    while ((SECONDS < deadline)); do
        if ax_tree 2>/dev/null | grep -Eq -- "$1"; then return 0; fi
        sleep 0.3
    done
    return 1
}

wait_gone() {
    local deadline=$((SECONDS + ${2:-10}))
    while ((SECONDS < deadline)); do
        if ! ax_tree 2>/dev/null | grep -Eq -- "$1"; then return 0; fi
        sleep 0.3
    done
    return 1
}

app_running() {
    osascript -e "on run argv" -e 'tell application "System Events" to return exists (processes whose name is (item 1 of argv))' \
        -e "end run" "$1"
}

remember_started() {
    if [[ "$(app_running "$1")" == false ]]; then printf '%s\n' "$1" >>"$started_file"; fi
}

cleanup() {
    local pid
    if pid="$(ciel_pid)"; then
        kill "$pid"
        for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
        if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid"; fi
        printf 'stopped Ciel %s\n' "$pid"
    fi
    if [[ -f "$started_file" ]]; then
        while IFS= read -r name; do
            osascript -e "on run argv" -e 'tell application (item 1 of argv) to quit' -e "end run" "$name" || true
            printf 'quit %s, which this script opened\n' "$name"
        done <"$started_file"
    fi
    if [[ -d "$target_dir" ]]; then
        osascript -e 'tell application "Finder"' -e 'repeat with w in (get every Finder window)' \
            -e 'if name of w is "ciel-verify-target" then close w' -e 'end repeat' -e 'end tell' || true
    fi
    rm -rf "$app" "$pid_file" "$started_file" "$target_dir"
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    if [[ -L "$evidence_root/latest" ]]; then printf 'evidence kept in %s\n' "$(evidence_dir)"; fi
}

step() {
    printf 'PASS %s\n' "$*"
}

journey_launcher_search() {
    press escape
    wait_gone 'Search apps and commands' 5 || fail "launcher-search: Escape did not close the launcher."
    step "launcher-search: Escape closes the launcher"
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "launcher-search: Control-Option-Space did not open the launcher."
    step "launcher-search: Control-Option-Space opens the launcher"
    type_text "left half"
    wait_for 'Left Half' 5 || fail "launcher-search: typing \"left half\" showed no Left Half row."
    snapshot launcher-search >/dev/null
    shot launcher-search >/dev/null
    step "launcher-search: \"left half\" lists the Left Half window command"
    type_text "zzqx"
    wait_gone 'Left Half' 5 || fail "launcher-search: a query with no match still lists Left Half."
    snapshot launcher-search-no-match >/dev/null
    step "launcher-search: a query with no match lists no rows"
    press escape
    wait_gone 'Search apps and commands' 5 || fail "launcher-search: Escape did not close the launcher."
}

journey_open_app() {
    remember_started TextEdit
    press escape
    wait_gone 'Search apps and commands' 5 || fail "open-app: Escape did not close the launcher."
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "open-app: Control-Option-Space did not open the launcher."
    type_text "textedit"
    wait_for 'TextEdit' 10 || fail "open-app: typing \"textedit\" showed no TextEdit row."
    snapshot open-app-results >/dev/null
    step "open-app: \"textedit\" lists TextEdit"
    press return
    wait_gone 'Search apps and commands' 5 || fail "open-app: Return did not close the launcher."
    for _ in {1..40}; do [[ "$(app_running TextEdit)" == true ]] && break; sleep 0.25; done
    [[ "$(app_running TextEdit)" == true ]] || fail "open-app: Return did not start TextEdit."
    shot open-app >/dev/null
    step "open-app: Return opens TextEdit and closes the launcher"
}

window_frame() {
    osascript -l JavaScript "$here/window-frame.js" "$@"
}

journey_window_commands() {
    mkdir -p "$target_dir"
    press escape
    wait_gone 'Search apps and commands' 5 || fail "window-commands: Escape did not close the launcher."
    osascript -e 'on run argv' -e 'tell application "Finder"' -e 'make new Finder window to (POSIX file (item 1 of argv))' \
        -e 'activate' -e 'end tell' -e 'end run' "$target_dir" >/dev/null
    sleep 1
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "window-commands: Control-Option-Space did not open the launcher."
    type_text "left half"
    wait_for 'Left Half' 5 || fail "window-commands: typing \"left half\" showed no Left Half row."
    press return
    wait_gone 'Search apps and commands' 5 || fail "window-commands: Return did not close the launcher."
    sleep 1
    local frame
    frame="$(window_frame Finder ciel-verify-target)" || fail "window-commands: cannot read the Finder window frame."
    printf '%s\n' "$frame" >"$(evidence_dir)/window-commands.frame.txt"
    shot window-commands >/dev/null
    grep -q '^left-half yes$' <<<"$frame" || fail "window-commands: the Finder window is not on the left half: $frame"
    step "window-commands: Left Half moves the front Finder window to the left half of the screen"
}

journey_settings() {
    press cmd+comma
    wait_for 'Ciel Settings' 5 || fail "settings: Command-Comma in the launcher did not open Ciel Settings."
    wait_for 'Launcher shortcut' 5 || fail "settings: Ciel Settings shows no Launcher shortcut recorder."
    snapshot settings >/dev/null
    shot settings >/dev/null
    step "settings: Command-Comma opens Ciel Settings with the Launcher shortcut recorder"
    close_window 'Ciel Settings'
    wait_gone 'Ciel Settings' 5 || fail "settings: the close button did not close Ciel Settings."
    step "settings: the close button closes Ciel Settings"
}

journey_onboarding() {
    wait_for 'Choose a shortcut' 5 || fail "onboarding: the first launch did not ask to choose a shortcut."
    snapshot onboarding >/dev/null
    shot onboarding >/dev/null
    step "onboarding: the first launch opens Set Up Ciel at Choose a shortcut"
}

journey() {
    local feature="$1"
    case "$feature" in
    launcher-search | open-app | window-commands | settings | onboarding) ;;
    all)
        for name in launcher-search open-app window-commands settings onboarding; do
            "$0" journey "$name"
        done
        return
        ;;
    *) fail "journey: unknown feature $feature" ;;
    esac
    trap cleanup EXIT
    if [[ "$feature" == onboarding ]]; then launch --fresh; else launch; fi
    doctor
    "journey_${feature//-/_}"
    printf 'PASS %s, evidence in %s\n' "$feature" "$(evidence_dir)"
}

[[ $# -ge 1 ]] || usage
command="$1"
shift
case "$command" in
launch) launch "$@" ;;
doctor) doctor ;;
press) [[ $# -eq 1 ]] || usage; press "$1" ;;
close) [[ $# -eq 1 ]] || usage; close_window "$1" ;;
type) [[ $# -eq 1 ]] || usage; type_text "$1" ;;
snapshot) [[ $# -eq 1 ]] || usage; snapshot "$1" ;;
shot) [[ $# -eq 1 ]] || usage; shot "$1" ;;
wait-for) [[ $# -ge 1 ]] || usage; wait_for "$@" || fail "wait-for: no match for $1" ;;
wait-gone) [[ $# -ge 1 ]] || usage; wait_gone "$@" || fail "wait-gone: $1 still matches" ;;
journey) [[ $# -eq 1 ]] || usage; journey "$1" ;;
cleanup) cleanup ;;
*) usage ;;
esac
