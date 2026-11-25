# Open an app

Return on an app result opens that app, brings it to the front and closes the launcher. Ciel remembers the pick, so the same query ranks that app higher next time.

## Sub-features

- `open-app-return` opens the selected app with Return.
- `open-app-close` closes the launcher after the app opens.
- `open-app-rescan` reloads the app list with the Rescan Applications command.

## How to get to it (user POV)

- Open the launcher, type part of an app name, and press Return.
- Double-click an app row.

## Driving it with ciel-verify.sh

Preconditions:

- The launcher is open after `launch`.
- TextEdit is installed (it ships with macOS) and is not running. The journey fails at once when it runs, because then Return proves nothing.

- **Find.** Close and reopen the launcher, then type `textedit`. Run `ciel-verify.sh press escape`, `ciel-verify.sh press ctrl+opt+space`, `ciel-verify.sh type textedit` and `ciel-verify.sh wait-for 'TextEdit' 10`. A `TextEdit` row is listed.
- **Open.** Press Return. Run `ciel-verify.sh press return`, then `ciel-verify.sh wait-gone 'Search apps and commands' 5`. A new `TextEdit` process runs and the launcher closes. The journey checks again just before Return that TextEdit is not running, and saves the new pid before it checks the launcher, so cleanup in CI stops it even when a later step fails.
- **Rescan.** Run `ciel-verify.sh press ctrl+opt+space`, `ciel-verify.sh type "rescan applications"` and `ciel-verify.sh press return`. Within 3 s the tree shows `Refreshing applications`, and the launcher closes.
- **Proof.** `journey open-app` saves `open-app-results.ax.txt` and `open-app.png`.

## Gotchas

- TextEdit opens its Open dialog at launch. That is TextEdit's behavior, not a Ciel failure.
- In CI, cleanup stops TextEdit by the pid the journey saved, after it checks that the pid still runs TextEdit. On your Mac it leaves TextEdit running and prints its pid, because the TextEdit that Return used can be one you opened.
