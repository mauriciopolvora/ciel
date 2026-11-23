# Window commands

The launcher lists window commands such as Left Half, Maximize and Center. Return on one moves and resizes the window that was in front when the launcher opened. Ciel never moves its own windows.

## Sub-features

- `window-left-half` puts the front window on the left half of its screen's visible area.
- `window-target` acts on the window that was in front before the launcher opened.

## How to get to it (user POV)

- Open the launcher over a window, type the command name, and press Return.
- Press a window shortcut set in Window Shortcuts (Settings > Window Shortcuts).

## Driving it with ciel-verify.sh

Preconditions:

- The launcher is open after `launch`.
- The terminal has Accessibility access, which the Ciel copy uses to move windows.

- **Target.** Close the launcher and open a Finder window on a new folder `.build/verify/ciel-verify-<pid>-<random>`, in front, at 700 x 500 points. The journey does this with AppleScript, because the user would have the window open already. The unique name makes sure the readback reads this window, and cleanup closes it by its Finder window id, saved as soon as Finder makes the window, only when that window still shows the folder. The journey reads the frame first and fails if the window already fills the left half.
- **Run.** Open the launcher, type `left half` and press Return. Run `ciel-verify.sh press ctrl+opt+space`, `ciel-verify.sh type "left half"`, `ciel-verify.sh wait-for 'Left Half' 5` and `ciel-verify.sh press return`. The launcher closes.
- **Read back.** `scripts/window-frame.js` reads the Finder window frame through System Events and picks the screen the window overlaps most, as Ciel does. After Return it compares the frame with the visible area of the screen the window started on, within 3 points, so a window that lands on another display fails. The journey reads it again for up to 5 s until it prints `left-half yes`. `window-commands.frame.txt` holds the frame before and after.
- **Proof.** `journey window-commands` saves `window-commands.frame.txt` and `window-commands.png`.

## Gotchas

- Without Accessibility access the command does nothing and Ciel shows a warning. `doctor` fails first.
- Apps apply a frame late and can clamp it. Read the frame again until it matches or the time runs out, as the journey does.
