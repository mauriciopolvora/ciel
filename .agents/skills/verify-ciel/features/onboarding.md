# Onboarding

The first launch opens Set Up Ciel. It asks the user to choose a launcher shortcut, then to allow window access, and then opens the launcher.

## Sub-features

- `onboarding-first-launch` opens Set Up Ciel at the Choose a shortcut page on a first launch.
- `onboarding-finish` closes Set Up Ciel and opens the launcher.

## How to get to it (user POV)

- Open Ciel for the first time.

## Driving it with ciel-verify.sh

Preconditions:

- `ciel-verify.sh launch --fresh` printed `PASS launch`, so the verify copy has no saved settings.

- **First launch.** Run `ciel-verify.sh wait-for 'Choose a shortcut' 5`. The `Set Up Ciel` window shows the `Choose a shortcut` page.
- **Finish.** Run `ciel-verify.sh click 'Set Up Ciel' 'Continue'`. With window access, Set Up Ciel closes and the launcher opens. Without it, the `Allow window control` page opens, and the journey presses `Not Now`, which opens the launcher.
- **Proof.** `journey onboarding` saves `onboarding.ax.txt`, `onboarding.png` and `onboarding-done.ax.txt`.

## Gotchas

- `Open Settings…` on the access page opens System Settings. Never press it unless the change under test is about access.
