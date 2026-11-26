---
name: verify-ciel
description: Drives the real Ciel macOS app the way a user does (the launcher shortcut, typing, Return, Settings, onboarding) and captures accessibility trees and screenshots as proof. Use to prove a Ciel change in the built app, to screenshot a Ciel screen, or when a native check passes but you need to see the user path work.
---

# Verify Ciel

Ciel is a menu bar launcher for macOS. A user presses Control-Option-Space, types, and presses Return to open an app or run a window command. This skill drives a disposable copy of the built app through those keys with System Events, reads Ciel's windows through the accessibility tree, and saves the proof.

Every command below runs from the repo root on a Mac. Agent hosts run Linux: there, the app journeys run only in CI, where the `Drive the built app with verify-ciel` step of `.github/workflows/checks.yml` runs `journey all` and uploads the `Ciel-verify-evidence` artifact. The site runs on Linux: its journeys are tagged Playwright Test specs in `e2e/`, and [features/site.md](features/site.md) says how the tags pick what runs.

## Launch

1. Build once: `bash scripts/build.sh`. It writes `dist/Ciel.app`. Rebuild after each source change.
2. Start the copy: `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh launch`. Add `--fresh` to see onboarding.

`launch` copies `dist/Ciel.app` to `.build/verify/CielVerify.app` with the bundle id from `Resources/Info.plist` plus `.verify` (`app.mauriciopolvora.ciel.verify`), so it reads and writes its own defaults and caches, never the installed Ciel's. It turns off Sparkle's update checks and, without `--fresh`, marks onboarding done, so the launcher opens at launch. It is ready when the accessibility tree shows the `Search apps and commands` field (or `Set Up Ciel` with `--fresh`), and it prints `PASS launch pid <pid>, evidence in <dir>`.

`launch` refuses to start while another Ciel runs or another run of this script holds the lock on `.build/verify/run.lock`, and a refused `launch` or `journey` leaves the running copy alone. Two copies fight over Control-Option-Space and the later one shows `Launcher shortcut unavailable`. Ask the operator to quit their Ciel. Never quit it for them.

## Doctor

Run `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh doctor` first whenever a step fails. Each line is `ok` or a `FAIL` that names the fix. Every `osascript` call stops after 20 s, so a stuck System Events fails the step instead of hanging. A wait starts no new read after its time is up, but a read that started before then can finish: with two windows open, one read can take about 5 s on a CI runner. It checks that the process is the copy this script started, that it runs as the verify bundle id, the build version, that the terminal has Accessibility access, and that Ciel shows no `Launcher shortcut unavailable` warning. The `launcher-search`, `open-app` and `window-commands` journeys prove the shortcut itself: each one closes the launcher and opens it again with Control-Option-Space.

The copy is started from the terminal, so it uses the terminal's Accessibility grant. That grant never touches the installed Ciel's grant. Never run `tccutil`.

## Drive

One feature end to end, with launch, doctor and cleanup included:

```bash
bash .agents/skills/verify-ciel/scripts/ciel-verify.sh journey launcher-search
```

The app features are `launcher-search`, `open-app`, `window-commands`, `settings` and `onboarding`. `journey all` runs each one in a new instance. Every step prints a `PASS` line. The first failure prints one `FAIL` line, exits 1, and still cleans up.

To drive by hand, launch, then use the same commands the journeys use. `press`, `type` and `close` refuse to send input when the copy is not running or another Ciel runs, so the keys never drive the installed Ciel:

| Command | What it does |
| --- | --- |
| `press ctrl+opt+space` | The launcher shortcut. Also `escape`, `return`, `tab`, `down`, `up`, `cmd+comma` |
| `close 'Ciel Settings'` | Clicks the close button of that Ciel window. Settings has no Command-W: Ciel has no main menu |
| `click 'Ciel Settings' 'Keyboard Guide…'` | Clicks the button with that title in that Ciel window. A failed click step saves `<step>-missing.ax.txt` and `.png` |
| `type "left half"` | Types into the focused field |
| `wait-for 'Left Half' 5` | Waits up to 5 s for a read of the accessibility tree to match an extended regex |
| `wait-gone 'Search apps and commands'` | Waits for a full read that no longer matches, such as the launcher closing. A failed read, or a tree with an `AXReadError` line, never counts as gone |
| `snapshot <name>` | Saves and prints the accessibility tree |
| `shot <name>` | Saves a screenshot of the whole screen |

Assert on the accessibility labels Ciel sets, never on coordinates or row order. The search field is `Search apps and commands`, the result list is `Search results`, each result row is `<title>, <subtitle>`, and the category button is `Search category: <name>`. Window titles are `Ciel` (the launcher), `Ciel Settings`, `Ciel Keyboard Guide`, `About Ciel`, `Window Shortcuts` and `Set Up Ciel`. [features/README.md](features/README.md) maps each feature to its recipe.

## Evidence

Each `launch` makes `.build/verify/evidence/<run id>/`, and `.build/verify/evidence/latest` points at it. A journey writes `<step>.ax.txt` (the accessibility tree after the action), `<step>.png`, any readback it makes (such as `window-commands.frame.txt`), and `ciel.log` with the app's output.

A proof drives the user path: the shortcut, the keys and the visible result. It never calls a check mode (`--ui-test` and the others in `check.sh`) or writes defaults that a user cannot set, other than the onboarding and update keys that `launch` sets. Capture the state after the action, not only the last screen. Check side effects outside Ciel too: the app that opened, or the window frame that changed. Paste the `PASS` lines in the PR body.

## Cleanup

`bash .agents/skills/verify-ciel/scripts/ciel-verify.sh cleanup` stops the Ciel copy by the pid it saved, in CI also stops each app that a journey started by the pid it saved, closes the Finder windows named after the folder that `window-commands` made for this run, keeps that folder (Finder shows "The file can't be found" when the folder of a window it just closed goes away), deletes the copy and its defaults, and keeps `.build/verify/evidence/`. It takes the same lock as `launch`, so it refuses while a journey runs, because that journey cleans up when it ends. Before each stop it checks that the pid still runs the same executable. It never stops an app by name. Outside CI it leaves the apps a journey opened running and prints their pids, because Launch Services can hand Return an instance the operator opened. A journey runs cleanup on exit, also after a failure, but only once its own `launch` has started a copy.

## Agent review of a site PR

The specs prove the flows they know. For a PR that changes something a user sees on the site, the PR reviewer (a different model from the author, the `ui agent reviewer` of `pstack-models.md`) serves `site/` with `cd site && bun run dev` and drives it with the Playwright CLI (`npx @playwright/cli`) for about 10 minutes:

1. It starts at the features of the tags that the PR changes, then tries the flows next to them: a reload, back and forward, empty and long demo input, a phone width.
2. It reproduces each failure a second time from a fresh page load. A failure that it reproduces twice is a **blocker** when it is a broken flow, a missing control, a failed readback, a console error or a 5xx response. A blocker makes the review request changes, with the steps, the URL and the evidence. A "looks off" note (spacing, copy) does not block.
3. For each blocker, the author first adds a spec with the feature tag that fails, then fixes the code in the same PR.

The gate is soft until 2026-12-10. A site PR can skip the review with the line `Agent review: skipped, <reason>` in the Verification section of its body. Count the skips with `gh pr list -R mauriciopolvora/ciel --state merged --search '"Agent review: skipped" in:body merged:>=2026-11-26'`.

## Gotchas

- The script needs Accessibility access for the terminal that runs it, for System Events key presses and for Ciel's window commands. The screenshot needs Screen Recording access. GitHub's macOS runners have both.
- System Events types into the key window. A click elsewhere during a run sends the keys to another app. The script checks that its copy runs and no other Ciel does, but it cannot see which app gets the keys. Do not touch the Mac while a journey runs.
- The accessibility tree treats an attribute it cannot read as empty. A `wait-gone` on a label can pass when only that label fails to read. Read the saved tree when a pass looks wrong.
- `journey open-app` fails at once when TextEdit is already running, because then it cannot prove that Return opened it. Quit TextEdit first.
- Dictation needs a microphone and the 600 MB speech model, so no journey covers it. The native checks in `check.sh` cover its pill and the press before the model is ready.
- No journey opens the menu bar icon's menu, so Window Shortcuts, License Notices and the other menu items stay unproven here.
