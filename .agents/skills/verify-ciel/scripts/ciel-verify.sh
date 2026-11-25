#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
run_dir="${CIEL_VERIFY_DIR:-$repo/.build/verify}"
evidence_root="$run_dir/evidence"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$repo/Resources/Info.plist").verify"
app="$run_dir/CielVerify.app"
binary="$app/Contents/MacOS/Ciel"
pid_file="$run_dir/ciel.pid"
started_file="$run_dir/started-apps"
finder_file="$run_dir/finder-window"
lock="$run_dir/run.lock"
owned=0

usage() {
    cat >&2 <<USAGE
Usage: ciel-verify.sh <command>
  launch [--fresh]        copy dist/Ciel.app as $bundle_id and start it.
                          --fresh keeps onboarding; without it the launcher opens at launch.
  doctor                  check that the instance is ours, alive and driveable.
  press <key>             press a key: ctrl+opt+space, escape, return, tab, down, up, cmd+comma.
  close <title>           click the close button of Ciel's window with that title.
  click <title> <button>  press the button with that title in Ciel's window with that title.
  type <text>             type text into the focused field.
  snapshot <name>         write the accessibility tree of Ciel's windows to <name>.ax.txt and print it.
  shot <name>             write a screenshot to <name>.png.
  wait-for <regex> [s]    wait until a read of the accessibility tree matches the extended regex (default 10 s).
  wait-gone <regex> [s]   wait until a read of the tree succeeds and no longer matches.
  journey <feature>       launch, doctor, drive one feature, clean up: launcher-search, open-app,
                          window-commands, settings, onboarding, or all.
  cleanup                 stop what this script started. Keeps the evidence.
Evidence goes to .build/verify/evidence/<run id>/, and .build/verify/evidence/latest points at the newest run.
USAGE
    exit 64
}

fail() {
    printf 'FAIL %s\n' "$*"
    exit 1
}

on_exit() {
    if [[ $owned -eq 1 ]]; then cleanup; fi
}
trap on_exit EXIT

osa() {
    perl -e 'alarm shift; exec @ARGV' "${osa_limit:-20}" osascript "$@"
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

pid_runs() {
    [[ "$(ps -p "$1" -o comm= 2>/dev/null)" == "$2" ]]
}

ciel_pid() {
    [[ -f "$pid_file" ]] || return 1
    local pid
    pid="$(cat "$pid_file")"
    pid_runs "$pid" "$binary" || return 1
    printf '%s\n' "$pid"
}

other_ciel() {
    local pid comm
    ps -axo pid=,comm= | while read -r pid comm; do
        if [[ "$comm" == */Contents/MacOS/Ciel && "$comm" != "$binary" ]]; then printf '%s %s\n' "$pid" "$comm"; fi
    done
}

take_lock() {
    mkdir -p "$run_dir"
    exec 9>>"$lock"
    perl -e 'use Fcntl ":flock"; open(my $fh, ">&=", 9) or exit 2; flock($fh, LOCK_EX | LOCK_NB) or exit 1' ||
        fail "$1: another run of this script is driving Ciel. Wait for it to end."
}

launch() {
    local fresh=0 others
    [[ "${1:-}" == --fresh ]] && fresh=1
    take_lock launch
    if ciel_pid >/dev/null; then fail "launch: an instance from this script is still running. Run cleanup first."; fi
    others="$(other_ciel)"
    if [[ -n "$others" ]]; then
        fail "launch: another Ciel is running and holds the launcher shortcut. Quit it first: $others"
    fi
    [[ -d "$repo/dist/Ciel.app" ]] || fail "launch: dist/Ciel.app is missing. Run bash scripts/build.sh first."
    owned=1
    mkdir -p "$run_dir"
    rm -rf "$app"
    ditto "$repo/dist/Ciel.app" "$app"
    /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
    codesign --force --sign - --preserve-metadata=entitlements,flags "$app" 2>/dev/null
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    defaults write "$bundle_id" SUEnableAutomaticChecks -bool false
    if [[ $fresh -eq 0 ]]; then defaults write "$bundle_id" onboarded -bool true; fi
    new_evidence_dir
    nohup "$binary" >"$(evidence_dir)/ciel.log" 2>&1 9>&- &
    printf '%s\n' "$!" >"$pid_file"
    disown
    local ready="Search apps and commands"
    [[ $fresh -eq 1 ]] && ready="Set Up Ciel"
    wait_for "$ready" 15 || fail "launch: Ciel did not show \"$ready\" within 15 s. See $(evidence_dir)/ciel.log."
    printf 'PASS launch pid %s, evidence in %s\n' "$(ciel_pid)" "$(evidence_dir)"
}

ax_tree() {
    local pid
    pid="$(ciel_pid)" || fail "no Ciel instance from this script is running. Run launch first."
    osa -l JavaScript "$here/ax-tree.js" "$pid"
}

ax_match() {
    local tree status=0
    tree="$(ax_tree 2>/dev/null)" || return 3
    if [[ "${2:-}" == complete ]] && grep -q 'AXReadError' <<<"$tree"; then return 3; fi
    grep -Eq -- "$1" <<<"$tree" || status=$?
    return "$status"
}

check_regex() {
    local status=0
    grep -Eq -- "$2" </dev/null || status=$?
    [[ $status -ne 2 ]] || fail "$1: grep cannot read the regex $2"
}

wait_for() {
    local deadline=$((SECONDS + ${2:-10})) status osa_limit remaining
    check_regex wait-for "$1"
    while :; do
        remaining=$((deadline - SECONDS))
        ((remaining > 0)) || return 1
        osa_limit=$((remaining < 20 ? remaining : 20))
        status=0
        ax_match "$1" || status=$?
        [[ $status -eq 0 ]] && return 0
        sleep 0.3
    done
    return 1
}

wait_gone() {
    local deadline=$((SECONDS + ${2:-10})) status osa_limit remaining
    check_regex wait-gone "$1"
    while :; do
        remaining=$((deadline - SECONDS))
        ((remaining > 0)) || return 1
        osa_limit=$((remaining < 20 ? remaining : 20))
        status=0
        ax_match "$1" complete || status=$?
        [[ $status -eq 1 ]] && return 0
        sleep 0.3
    done
    return 1
}

doctor() {
    local pid trusted tree
    pid="$(ciel_pid)" || fail "doctor: no Ciel instance from this script is running."
    printf 'ok   process %s runs %s\n' "$pid" "$binary"
    [[ "$(defaults read "$app/Contents/Info" CFBundleIdentifier)" == "$bundle_id" ]] ||
        fail "doctor: the copy does not run as $bundle_id."
    printf 'ok   bundle id %s, so the installed Ciel keeps its settings\n' "$bundle_id"
    printf 'ok   build %s\n' "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)"
    trusted="$(osa -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()')"
    [[ "$trusted" == true ]] ||
        fail "doctor: this terminal has no Accessibility access. Grant it in System Settings > Privacy & Security > Accessibility."
    printf 'ok   Accessibility access for the driver and the Ciel it started\n'
    tree="$(ax_tree)" || fail "doctor: System Events cannot read Ciel's windows."
    if grep -q 'Launcher shortcut unavailable' <<<"$tree"; then
        fail "doctor: Ciel could not register the launcher shortcut. Another app holds Control-Option-Space."
    fi
    printf 'ok   Ciel answers System Events and shows no shortcut warning\n'
}

guard_input() {
    local others
    ciel_pid >/dev/null || fail "$1: no Ciel instance from this script is running, so the keys could reach another app. Run launch first."
    others="$(other_ciel)"
    [[ -z "$others" ]] || fail "$1: another Ciel is running, so the keys could drive it instead of the copy: $others"
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
    guard_input press
    osa -e "tell application \"System Events\" to key code $code$mods"
}

close_window() {
    local pid
    guard_input close
    pid="$(ciel_pid)"
    osa -e 'on run argv' -e 'tell application "System Events" to tell (first process whose unix id is (item 1 of argv as integer))' \
        -e 'click (first button of window (item 2 of argv) whose subrole is "AXCloseButton")' -e 'end tell' -e 'end run' \
        "$pid" "$1" >/dev/null
}

click_button() {
    local pid
    guard_input click
    pid="$(ciel_pid)"
    osa -l JavaScript "$here/press-button.js" "$pid" "$1" "$2" >/dev/null
}

type_text() {
    guard_input type
    osa -e 'on run argv' -e 'tell application "System Events" to keystroke (item 1 of argv)' -e 'end run' "$1"
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

app_pid() {
    pgrep -x "$1" | head -1 || true
}

stop_started_apps() {
    [[ -f "$started_file" ]] || return 0
    local pid comm
    while IFS=$'\t' read -r pid comm; do
        pid_runs "$pid" "$comm" || continue
        if [[ "${CI:-}" == true ]]; then
            kill -TERM "$pid" 2>/dev/null || true
            printf 'stopped %s %s, which this script opened\n' "$comm" "$pid"
        else
            printf 'left %s %s running: Launch Services can hand Return an instance you opened, so only CI stops it\n' "$comm" "$pid"
        fi
    done <"$started_file"
}

close_finder_window() {
    [[ -f "$finder_file" ]] || return 0
    local dir
    dir="$(cat "$finder_file")"
    [[ -n "$dir" ]] || return 0
    osa -e 'on run argv' -e 'tell application "Finder" to close (every Finder window whose name is (item 1 of argv))' -e 'end run' \
        "$(basename "$dir")" >/dev/null || true
    rm -rf "$dir"
}

cleanup() {
    local pid
    if pid="$(ciel_pid)"; then
        kill "$pid" 2>/dev/null || true
        for _ in {1..20}; do pid_runs "$pid" "$binary" || break; sleep 0.25; done
        if pid_runs "$pid" "$binary"; then kill -9 "$pid" 2>/dev/null || true; fi
        printf 'stopped Ciel %s\n' "$pid"
    fi
    stop_started_apps
    close_finder_window
    rm -rf "$app" "$pid_file" "$started_file" "$finder_file"
    defaults delete "$bundle_id" >/dev/null 2>&1 || true

    if [[ -L "$evidence_root/latest" ]]; then printf 'evidence kept in %s\n' "$(evidence_dir)"; fi
}

step() {
    printf 'PASS %s\n' "$*"
}

reopen_launcher() {
    press escape
    wait_gone 'Search apps and commands' 5 || fail "$1: Escape did not close the launcher."
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "$1: Control-Option-Space did not open the launcher."
}

journey_launcher_search() {
    press escape
    wait_gone 'Search apps and commands' 5 || fail "launcher-search: Escape did not close the launcher."
    step "launcher-search: Escape closes the launcher"
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "launcher-search: Control-Option-Space did not open the launcher."
    step "launcher-search: Control-Option-Space opens the launcher"
    type_text "left half"
    wait_for 'AXCell description="Left Half, ' 5 || fail "launcher-search: typing \"left half\" showed no Left Half row."
    snapshot launcher-search >/dev/null
    shot launcher-search >/dev/null
    step "launcher-search: \"left half\" lists the Left Half window command"
    press tab
    wait_for 'description="Search category: Apps"' 5 || fail "launcher-search: Tab did not switch the category to Apps."
    wait_gone 'AXCell description="Left Half, ' 5 || fail "launcher-search: the Apps category still lists the Left Half window command."
    step "launcher-search: Tab switches to Apps, which hides the Left Half window command"
    press tab
    wait_for 'description="Search category: Windows"' 5 || fail "launcher-search: a second Tab did not switch the category to Windows."
    wait_for 'AXCell description="Left Half, ' 5 || fail "launcher-search: the Windows category does not list Left Half."
    snapshot launcher-search-windows >/dev/null
    step "launcher-search: a second Tab switches to Windows, which lists Left Half again"
    press tab
    wait_for 'description="Search category: All"' 5 || fail "launcher-search: a third Tab did not switch the category back to All."
    step "launcher-search: a third Tab switches back to All"
    type_text "zzqx"
    wait_for 'value="No matches"' 5 || fail "launcher-search: a query with no match does not say No matches."
    snapshot launcher-search-no-match >/dev/null
    if grep -qE 'AXRow|AXReadError' "$(evidence_dir)/launcher-search-no-match.ax.txt"; then
        fail "launcher-search: a query with no match still lists rows, or part of the tree could not be read."
    fi
    step "launcher-search: a query with no match lists no rows and says No matches"
    press escape
    wait_gone 'Search apps and commands' 5 || fail "launcher-search: Escape did not close the launcher."
}

journey_open_app() {
    local pid comm
    [[ -z "$(app_pid TextEdit)" ]] ||
        fail "open-app: TextEdit is already running, so the journey cannot prove that Return opens it. Quit TextEdit first."
    reopen_launcher open-app
    type_text "textedit"
    wait_for 'AXCell description="TextEdit, ' 10 || fail "open-app: typing \"textedit\" showed no TextEdit row."
    snapshot open-app-results >/dev/null
    step "open-app: \"textedit\" lists TextEdit"
    [[ -z "$(app_pid TextEdit)" ]] || fail "open-app: TextEdit started before Return, so the journey cannot prove that Return opens it."
    press return
    for _ in {1..40}; do
        pid="$(app_pid TextEdit)"
        [[ -n "$pid" ]] && break
        sleep 0.25
    done
    [[ -n "$pid" ]] || fail "open-app: Return did not start TextEdit."
    comm="$(ps -p "$pid" -o comm=)"
    printf '%s\t%s\n' "$pid" "$comm" >>"$started_file"
    wait_gone 'Search apps and commands' 5 || fail "open-app: Return did not close the launcher."
    shot open-app >/dev/null
    step "open-app: Return opens TextEdit (pid $pid) and closes the launcher"
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "open-app: Control-Option-Space did not open the launcher over TextEdit."
    type_text "rescan applications"
    wait_for 'AXCell description="Rescan Applications, ' 5 || fail "open-app: typing \"rescan applications\" showed no Rescan Applications row."
    press return
    wait_for 'value="Refreshing applications"' 3 || fail "open-app: Return on Rescan Applications showed no Refreshing applications message."
    wait_gone 'Search apps and commands' 5 || fail "open-app: Return on Rescan Applications did not close the launcher."
    step "open-app: Return on Rescan Applications closes the launcher and shows Refreshing applications"
}

window_frame() {
    osa -l JavaScript "$here/window-frame.js" "$@"
}

journey_window_commands() {
    local name="ciel-verify-$$-$RANDOM" dir frame="" got=0 screen
    dir="$run_dir/$name"
    mkdir -p "$dir"
    press escape
    wait_gone 'Search apps and commands' 5 || fail "window-commands: Escape did not close the launcher."
    printf '%s\n' "$dir" >"$finder_file"
    osa -e 'on run argv' -e 'tell application "Finder"' -e 'set w to make new Finder window to (POSIX file (item 1 of argv))' \
        -e 'set bounds of w to {120, 160, 820, 660}' -e 'activate' -e 'end tell' -e 'end run' "$dir" >/dev/null ||
        fail "window-commands: Finder did not open a 700 x 500 window on $dir."
    for _ in {1..20}; do
        if frame="$(window_frame Finder "$name" 2>/dev/null)"; then got=1 && break; fi
        sleep 0.25
    done
    [[ $got -eq 1 ]] || fail "window-commands: cannot read the frame of the Finder window $name."
    printf 'before\n%s\n' "$frame" >"$(evidence_dir)/window-commands.frame.txt"
    grep -q '^left-half no$' <<<"$frame" || fail "window-commands: the Finder window starts on the left half: $frame"
    screen="$(sed -n 's/^screen //p' <<<"$frame")"
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "window-commands: Control-Option-Space did not open the launcher."
    type_text "left half"
    wait_for 'AXCell description="Left Half, ' 5 || fail "window-commands: typing \"left half\" showed no Left Half row."
    press return
    wait_gone 'Search apps and commands' 5 || fail "window-commands: Return did not close the launcher."
    for _ in {1..20}; do
        frame="$(window_frame Finder "$name" "$screen")" || fail "window-commands: cannot read the frame of the Finder window $name."
        grep -q '^left-half yes$' <<<"$frame" && break
        sleep 0.25
    done
    printf 'after\n%s\n' "$frame" >>"$(evidence_dir)/window-commands.frame.txt"
    shot window-commands >/dev/null
    grep -q '^left-half yes$' <<<"$frame" || fail "window-commands: the Finder window is not on the left half: $frame"
    step "window-commands: Left Half moves the front Finder window from 700 x 500 to the left half of screen $screen, where it started"
    run_window_command maximize Maximize "$name" "$screen" '^maximized yes$'
    step "window-commands: Maximize fills the visible area of screen $screen with the Finder window"
    run_window_command "restore previous size" "Restore Previous Size" "$name" "$screen" '^left-half yes$'
    step "window-commands: Restore Previous Size puts the Finder window back on the left half"
}

run_window_command() {
    local query="$1" title="$2" name="$3" screen="$4" expected="$5" frame=""
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "window-commands: Control-Option-Space did not open the launcher."
    type_text "$query"
    wait_for "AXCell description=\"$title, " 5 || fail "window-commands: typing \"$query\" showed no $title row."
    press return
    wait_gone 'Search apps and commands' 5 || fail "window-commands: Return on $title did not close the launcher."
    for _ in {1..20}; do
        frame="$(window_frame Finder "$name" "$screen")" || fail "window-commands: cannot read the frame of the Finder window $name."
        grep -q "$expected" <<<"$frame" && break
        sleep 0.25
    done
    printf 'after %s\n%s\n' "$title" "$frame" >>"$(evidence_dir)/window-commands.frame.txt"
    grep -q "$expected" <<<"$frame" || fail "window-commands: $title did not give the expected frame: $frame"
}

journey_settings() {
    local recorder='AXButton title="⌃⌥Space" description="Launcher shortcut"'
    press cmd+comma
    wait_for 'AXWindow title="Ciel Settings"' 5 || fail "settings: Command-Comma in the launcher did not open Ciel Settings."
    wait_for "$recorder" 5 || fail "settings: Ciel Settings shows no Launcher shortcut recorder set to Control-Option-Space."
    snapshot settings >/dev/null
    awk '/^AXWindow/ { inside = /title="Ciel Settings"/ } inside' "$(evidence_dir)/settings.ax.txt" | grep -qF "$recorder" ||
        fail "settings: the Launcher shortcut recorder is not in the Ciel Settings window."
    shot settings >/dev/null
    step "settings: Command-Comma opens Ciel Settings with the Launcher shortcut recorder set to Control-Option-Space"
    close_window 'Ciel Settings'
    wait_gone 'AXWindow title="Ciel Settings"' 5 || fail "settings: the close button did not close Ciel Settings."
    step "settings: the close button closes Ciel Settings"
    press ctrl+opt+space
    wait_for 'Search apps and commands' 5 || fail "settings: Control-Option-Space did not open the launcher."
    type_text "ciel settings"
    wait_for 'AXCell description="Ciel Settings, ' 5 || fail "settings: typing \"ciel settings\" showed no Ciel Settings row."
    press return
    wait_for 'AXWindow title="Ciel Settings"' 5 || fail "settings: Return on Ciel Settings did not open Ciel Settings."
    wait_gone 'Search apps and commands' 5 || fail "settings: Return on Ciel Settings did not close the launcher."
    step "settings: Return on the Ciel Settings command opens Ciel Settings"
    click_button 'Ciel Settings' 'Keyboard Guide…'
    wait_for 'AXWindow title="Ciel Keyboard Guide"' 5 || fail "settings: Keyboard Guide… did not open Ciel Keyboard Guide."
    wait_for 'value="Change search category"' 5 || fail "settings: Ciel Keyboard Guide does not list the Tab key."
    snapshot settings-guide >/dev/null
    shot settings-guide >/dev/null
    close_window 'Ciel Keyboard Guide'
    wait_gone 'AXWindow title="Ciel Keyboard Guide"' 5 || fail "settings: the close button did not close Ciel Keyboard Guide."
    step "settings: Keyboard Guide… opens Ciel Keyboard Guide with the key list, and its close button closes it"
    click_button 'Ciel Settings' 'About Ciel…'
    wait_for 'AXWindow title="About Ciel"' 5 || fail "settings: About Ciel… did not open About Ciel."
    snapshot settings-about >/dev/null
    close_window 'About Ciel'
    wait_gone 'AXWindow title="About Ciel"' 5 || fail "settings: the close button did not close About Ciel."
    close_window 'Ciel Settings'
    wait_gone 'AXWindow title="Ciel Settings"' 5 || fail "settings: the close button did not close Ciel Settings."
    step "settings: About Ciel… opens About Ciel, and the close buttons close it and Ciel Settings"
}

journey_onboarding() {
    wait_for 'Choose a shortcut' 5 || fail "onboarding: the first launch did not ask to choose a shortcut."
    snapshot onboarding >/dev/null
    shot onboarding >/dev/null
    step "onboarding: the first launch opens Set Up Ciel at Choose a shortcut"
    click_button 'Set Up Ciel' 'Continue'
    wait_for 'Search apps and commands|Allow window control' 5 ||
        fail "onboarding: Continue did not open the launcher or the Allow window control page."
    if ! ax_match 'Search apps and commands'; then
        step "onboarding: Continue opens Allow window control, because the Ciel copy has no Accessibility access"
        click_button 'Set Up Ciel' 'Not Now'
        wait_for 'Search apps and commands' 5 || fail "onboarding: Not Now did not open the launcher."
    fi
    wait_gone 'AXWindow title="Set Up Ciel"' 5 || fail "onboarding: Set Up Ciel is still open after the launcher opened."
    snapshot onboarding-done >/dev/null
    step "onboarding: finishing Set Up Ciel closes it and opens the launcher"
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
    if [[ "$feature" == onboarding ]]; then launch --fresh; else launch; fi
    doctor
    "journey_${feature//-/_}"
    printf 'PASS %s, evidence in %s\n' "$feature" "$(evidence_dir)"
}

[[ $# -ge 1 ]] || usage
command="$1"
shift
case "$command" in
launch)
    launch "$@"
    owned=0
    ;;
doctor) doctor ;;
press) [[ $# -eq 1 ]] || usage; press "$1" ;;
close) [[ $# -eq 1 ]] || usage; close_window "$1" ;;
type) [[ $# -eq 1 ]] || usage; type_text "$1" ;;
snapshot) [[ $# -eq 1 ]] || usage; snapshot "$1" ;;
shot) [[ $# -eq 1 ]] || usage; shot "$1" ;;
wait-for) [[ $# -ge 1 ]] || usage; wait_for "$@" || fail "wait-for: no match for $1" ;;
wait-gone) [[ $# -ge 1 ]] || usage; wait_gone "$@" || fail "wait-gone: $1 still matches, or the tree cannot be read" ;;
journey) [[ $# -eq 1 ]] || usage; journey "$1" ;;
cleanup)
    take_lock cleanup
    cleanup
    ;;
*) usage ;;
esac
