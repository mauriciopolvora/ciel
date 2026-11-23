# Launcher search

The launcher is a black panel with one search field. Control-Option-Space opens and closes it from any app. Typing lists matching apps and commands at once, and Escape closes it.

## Sub-features

- `search-open` opens the launcher with the shortcut, focused on the search field.
- `search-match` lists the matching rows for a query.
- `search-no-match` lists no rows for a query that matches nothing.
- `search-close` closes the launcher with Escape.

## How to get to it (user POV)

- Press Control-Option-Space in any app.
- Choose Open Ciel in the menu bar icon's menu.
- Open Ciel from Applications while it runs.

## Driving it with ciel-verify.sh

Preconditions:

- `ciel-verify.sh launch` printed `PASS launch`, so the launcher is open.

- **Close.** Press Escape. Run `ciel-verify.sh press escape`, then `ciel-verify.sh wait-gone 'Search apps and commands' 5`. The launcher window is gone.
- **Open.** Press the shortcut. Run `ciel-verify.sh press ctrl+opt+space`, then `ciel-verify.sh wait-for 'Search apps and commands' 5`. The search field is back.
- **Match.** Type `left half`. Run `ciel-verify.sh type "left half"`, then `ciel-verify.sh wait-for 'Left Half' 5`. The tree lists a `Left Half` row.
- **No match.** Type `zzqx` after it. Run `ciel-verify.sh type zzqx`, then `ciel-verify.sh wait-gone 'Left Half' 5`. No row is left.
- **Proof.** `journey launcher-search` saves `launcher-search.ax.txt`, `launcher-search.png` and `launcher-search-no-match.ax.txt`.

## Gotchas

- The launcher opens at launch, so the first shortcut press would close it. Press Escape first, as the journey does.
- App rows come from a catalog that loads after launch. Wait for an app row; window command rows are there at once.
