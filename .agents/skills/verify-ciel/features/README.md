# Ciel verification map

This directory is the maintained source for verifying what a Ciel user sees. Read this index, then use the matching feature file as the recipe. Every command runs from the repo root through `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh`, written `ciel-verify.sh` below.

## Baseline preconditions

- `dist/Ciel.app` is built from the commit under test (`bash scripts/build.sh`).
- No other Ciel is running. `launch` refuses to start next to one.
- The terminal has Accessibility and Screen Recording access.
- `ciel-verify.sh doctor` prints only `ok` lines.

## Driving conventions

- Start each recipe from a new `launch`. A `journey` does this for you.
- Find elements by the accessibility labels in SKILL.md, never by coordinates or row order.
- Wait with `wait-for` or `wait-gone`, never a fixed sleep. Results update as the catalog loads.
- Keep queries literal. The search matches titles and keywords, so a changed query proves a different thing.

## Proof and skip reporting

- Each journey saves the accessibility trees, screenshots and readbacks that its feature file names, under `.build/verify/evidence/latest/`.
- A side effect outside Ciel (an app that opened, a window that moved) is read back from that app, not from Ciel.
- Report a step that cannot run with the command you ran and the unmet precondition. Never report it as verified through another path.

## Feature entry contract

Each feature file starts with an H1 and one paragraph on what the user sees. Then four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with ciel-verify.sh`, `Gotchas`.

## Features

- [Launcher search](./launcher-search.md): the shortcut opens the launcher, typing lists matches, Escape closes it.
- [Open an app](./open-app.md): Return on an app result opens the app and closes the launcher.
- [Window commands](./window-commands.md): Return on a window command moves the window that was in front.
- [Settings](./settings.md): Command-Comma in the launcher opens Ciel Settings.
- [Onboarding](./onboarding.md): the first launch opens Set Up Ciel.
