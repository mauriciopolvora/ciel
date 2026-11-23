---
name: verify-ciel
description: Drives the real Ciel macOS app the way a user does (the launcher shortcut, typing, Return, Settings, onboarding) and captures accessibility trees and screenshots as proof. Use to prove a Ciel change in the built app, to screenshot a Ciel screen, or when a native check passes but you need to see the user path work.
---

# Verify Ciel

Ciel is a menu bar launcher for macOS. A user presses Control-Option-Space, types, and presses Return to open an app or run a window command. This skill drives a disposable copy of the built app through those keys with System Events, reads Ciel's windows through the accessibility tree, and saves the proof.

Every command below runs from the repo root on a Mac. Agent hosts run Linux: there, this skill runs only in CI, where the `Drive the built app with verify-ciel` step of `.github/workflows/checks.yml` runs `journey all` and uploads the `Ciel-verify-evidence` artifact.

## Launch

1. Build once: `bash scripts/build.sh`. It writes `dist/Ciel.app`. Rebuild after each source change.
2. Start the copy: `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh launch`. Add `--fresh` to see onboarding.

`launch` copies `dist/Ciel.app` to `.build/verify/CielVerify.app` with the bundle id from `Resources/Info.plist` plus `.verify` (`app.mauriciopolvora.ciel.verify`), so it reads and writes its own defaults and caches, never the installed Ciel's. It turns off Sparkle's update checks and, without `--fresh`, marks onboarding done, so the launcher opens at launch. It is ready when the accessibility tree shows the `Search apps and commands` field (or `Set Up Ciel` with `--fresh`), and it prints `PASS launch pid <pid>, evidence in <dir>`.

`launch` refuses to start while another Ciel runs, and a refused `launch` or `journey` leaves the running copy alone. Two copies fight over Control-Option-Space and the later one shows `Launcher shortcut unavailable`. Ask the operator to quit their Ciel. Never quit it for them.

## Doctor

Run `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh doctor` first whenever a step fails. Each line is `ok` or a `FAIL` that names the fix. Every `osascript` call stops after 20 s, so a stuck System Events fails the step instead of hanging. It checks that the process is the copy this script started, that it runs as the verify bundle id, the build version, that the terminal has Accessibility access, and that Ciel shows no `Launcher shortcut unavailable` warning. The journeys prove the shortcut itself: each one closes the launcher and opens it again with Control-Option-Space.

The copy is started from the terminal, so it uses the terminal's Accessibility grant. That grant never touches the installed Ciel's grant. Never run `tccutil`.

## Drive

One feature end to end, with launch, doctor and cleanup included:

```bash
bash .agents/skills/verify-ciel/scripts/ciel-verify.sh journey launcher-search
```

The features are `launcher-search`, `open-app`, `window-commands`, `settings` and `onboarding`. `journey all` runs each one in a new instance. Every step prints a `PASS` line. The first failure prints one `FAIL` line, exits 1, and still cleans up.

To drive by hand, launch, then use the same commands the journeys use:

| Command | What it does |
| --- | --- |
| `press ctrl+opt+space` | The launcher shortcut. Also `escape`, `return`, `tab`, `down`, `up`, `cmd+comma` |
| `close 'Ciel Settings'` | Clicks the close button of that Ciel window. Settings has no Command-W: Ciel has no main menu |
| `type "left half"` | Types into the focused field |
| `wait-for 'Left Half' 5` | Waits up to 5 s for a read of the accessibility tree to match an extended regex |
| `wait-gone 'Search apps and commands'` | Waits for a read that succeeds and no longer matches, such as the launcher closing. A failed read never counts as gone |
| `snapshot <name>` | Saves and prints the accessibility tree |
| `shot <name>` | Saves a screenshot of the whole screen |

Assert on the accessibility labels Ciel sets, never on coordinates or row order. The search field is `Search apps and commands`, the result list is `Search results`, each result row is `<title>, <subtitle>`, and the category button is `Search category: <name>`. Window titles are `Ciel` (the launcher), `Ciel Settings`, `Window Shortcuts` and `Set Up Ciel`. [features/README.md](features/README.md) maps each feature to its recipe.

## Evidence

Each `launch` makes `.build/verify/evidence/<run id>/`, and `.build/verify/evidence/latest` points at it. A journey writes `<step>.ax.txt` (the accessibility tree after the action), `<step>.png`, any readback it makes (such as `window-commands.frame.txt`), and `ciel.log` with the app's output.

A proof drives the user path: the shortcut, the keys and the visible result. It never calls a check mode (`--ui-test` and the others in `check.sh`) or writes defaults that a user cannot set, other than the onboarding and update keys that `launch` sets. Capture the state after the action, not only the last screen. Check side effects outside Ciel too: the app that opened, or the window frame that changed. Paste the `PASS` lines in the PR body.

## Cleanup

`bash .agents/skills/verify-ciel/scripts/ciel-verify.sh cleanup` stops the Ciel copy by the pid it saved, stops each app that a journey started by the pid it saved, closes the Finder window that `window-commands` opened by its window id, deletes the copy and its defaults, and keeps `.build/verify/evidence/`. Before each stop it checks that the pid still runs the same executable. It never stops or closes anything by name. A journey runs cleanup on exit, also after a failure, but only once its own `launch` has started a copy.

## Gotchas

- The script needs Accessibility access for the terminal that runs it, for System Events key presses and for Ciel's window commands. The screenshot needs Screen Recording access. GitHub's macOS runners have both.
- System Events types into the key window. A click elsewhere during a run sends the keys to another app.
- `journey open-app` fails at once when TextEdit is already running, because then it cannot prove that Return opened it. Quit TextEdit first.
- Dictation needs a microphone and the 600 MB speech model, so no journey covers it. The native checks in `check.sh` cover its pill and the press before the model is ready.
