# Settings

Ciel Settings is one black window with the launcher shortcut, window shortcuts, speech to text, updates and the About link. Command-Comma in the launcher opens it on the launcher's screen.

## Sub-features

- `settings-open` opens Ciel Settings with Command-Comma from the launcher.
- `settings-close` closes it with the close button.

## How to get to it (user POV)

- Press Command-Comma while the launcher is open.
- Choose Settings in the menu bar icon's menu.
- Type `settings` in the launcher and press Return.

## Driving it with ciel-verify.sh

Preconditions:

- The launcher is open after `launch`.

- **Open.** Press Command-Comma. Run `ciel-verify.sh press cmd+comma`, then `ciel-verify.sh wait-for 'Ciel Settings' 5`. The tree shows the `Ciel Settings` window with the `Launcher shortcut` recorder.
- **Close.** Click the close button. Run `ciel-verify.sh close 'Ciel Settings'`, then `ciel-verify.sh wait-gone 'Ciel Settings' 5`. The window is gone.
- **Proof.** `journey settings` saves `settings.ax.txt` and `settings.png`.

## Gotchas

- Changing a shortcut here can open System Settings when Spotlight holds it. Leave the shortcuts as they are unless the change under test is about them.
- Command-W does not close Settings. Ciel runs without a main menu, so no Close item takes the shortcut. Use the close button, as a user does.
