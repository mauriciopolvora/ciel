# Onboarding

The first launch opens Set Up Ciel. It asks the user to choose a launcher shortcut, then to allow window access, and then opens the launcher.

## Sub-features

- `onboarding-first-launch` opens Set Up Ciel at the Choose a shortcut page on a first launch.

## How to get to it (user POV)

- Open Ciel for the first time.

## Driving it with ciel-verify.sh

Preconditions:

- `ciel-verify.sh launch --fresh` printed `PASS launch`, so the verify copy has no saved settings.

- **First launch.** Run `ciel-verify.sh wait-for 'Choose a shortcut' 5`. The `Set Up Ciel` window shows the `Choose a shortcut` page.
- **Proof.** `journey onboarding` saves `onboarding.ax.txt` and `onboarding.png`.

## Gotchas

- The access page opens System Settings. Stop at the shortcut page unless the change under test is about access.
