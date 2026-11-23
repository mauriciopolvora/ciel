# Open an app

Return on an app result opens that app, brings it to the front and closes the launcher. Ciel remembers the pick, so the same query ranks that app higher next time.

## Sub-features

- `open-app-return` opens the selected app with Return.
- `open-app-close` closes the launcher after the app opens.

## How to get to it (user POV)

- Open the launcher, type part of an app name, and press Return.
- Double-click an app row.

## Driving it with ciel-verify.sh

Preconditions:

- The launcher is open after `launch`.
- TextEdit is installed (it ships with macOS). The journey records whether it was already running.

- **Find.** Close and reopen the launcher, then type `textedit`. Run `ciel-verify.sh press escape`, `ciel-verify.sh press ctrl+opt+space`, `ciel-verify.sh type textedit` and `ciel-verify.sh wait-for 'TextEdit' 10`. A `TextEdit` row is listed.
- **Open.** Press Return. Run `ciel-verify.sh press return`, then `ciel-verify.sh wait-gone 'Search apps and commands' 5`. The launcher closes and System Events lists a running `TextEdit` process.
- **Proof.** `journey open-app` saves `open-app-results.ax.txt` and `open-app.png`.

## Gotchas

- TextEdit opens its Open dialog at launch. That is TextEdit's behavior, not a Ciel failure.
- Cleanup quits TextEdit only when the journey started it.
