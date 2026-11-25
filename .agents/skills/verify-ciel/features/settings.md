# Settings

Ciel Settings is one black window with the launcher shortcut, window shortcuts, speech to text, updates and the About link. Command-Comma in the launcher opens it on the launcher's screen.

## Sub-features

- `settings-open` opens Ciel Settings with Command-Comma from the launcher.
- `settings-close` closes it with the close button.
- `settings-command` opens it with the Ciel Settings command in the launcher.
- `settings-guide` and `settings-about` open Ciel Keyboard Guide and About Ciel from their buttons.

## How to get to it (user POV)

- Press Command-Comma while the launcher is open.
- Choose Settings in the menu bar icon's menu.
- Type `ciel settings` in the launcher and press Return.

## Driving it with ciel-verify.sh

Preconditions:

- The launcher is open after `launch`.

- **Open.** Press Command-Comma. Run `ciel-verify.sh press cmd+comma`, then `ciel-verify.sh wait-for 'Ciel Settings' 5`. The tree shows the `Ciel Settings` window, and inside it the recorder `AXButton title="⌃⌥Space" description="Launcher shortcut"`.
- **Close.** Click the close button. Run `ciel-verify.sh close 'Ciel Settings'`, then `ciel-verify.sh wait-gone 'Ciel Settings' 5`. The window is gone.
- **Command.** Run `ciel-verify.sh press ctrl+opt+space`, `ciel-verify.sh type "ciel settings"` and `ciel-verify.sh press return`. `Ciel Settings` opens and the launcher closes.
- **Guide and About.** Run `ciel-verify.sh click 'Ciel Settings' 'Keyboard Guide…'`. `Ciel Keyboard Guide` opens and lists `Change search category`. Close it, then `ciel-verify.sh click 'Ciel Settings' 'About Ciel…'` opens `About Ciel`.
- **Proof.** `journey settings` saves `settings.ax.txt`, `settings.png`, `settings-guide.ax.txt`, `settings-guide.png` and `settings-about.ax.txt`.

## Gotchas

- Changing a shortcut here can open System Settings when Spotlight holds it. Leave the shortcuts as they are unless the change under test is about them.
- Command-W does not close Settings. Ciel runs without a main menu, so no Close item takes the shortcut. Use the close button, as a user does.
