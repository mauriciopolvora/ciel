# Local usage history

Ciel records successful app launches from the launcher. It also records successful window commands, from the launcher or from a window shortcut. It saves a use count and last-used time in the `app.mauriciopolvora.ciel` preferences domain. A launch or command from the launcher also saves a pick: the text you typed and the entry you chose. Ciel keeps the newest 500 picks. It does not use a server, AI model, or background activity monitor.

Search first finds the entries that match the typed text. An entry that does not match is never shown, whatever its history. Results then rank in this order:

1. An exact title match, so typing `code` shows Code above Codex.
2. Learned picks. A pick counts when its saved text starts with what you type. If you chose First Three Fourths after typing `first t`, it ranks first for `f`, `fir` and `first t`. The entry picked more often for that text wins.
3. Text match strength. Use count adds a small, capped bonus.
4. Recent use, then title.

Picks are saved in lowercase, without accents and with single spaces, the same form search compares against. A window shortcut records use but saves no pick, since nothing was typed. The interface shows results only for a query with searchable text. The empty launcher does not display usage suggestions. No settings page or database is required.

Minimize is included in the command catalog. macOS can accept the Accessibility change before the Dock animation updates the minimized state. The controller confirms the state on its background window queue, with a one-second limit, before it records success.

## Checks

The unit tests cover history ranking, learned picks, recent-use ties, empty queries, exact text priority, saved history and picks, and preservation of old counts. Mutant M33 checks that a pick counts for shorter typed text. Run `bash scripts/check.sh --unit-only`.

The native window check in `bash scripts/check.sh` covers geometry, restore, display movement, and minimize. It needs Accessibility access for the app that runs `check.sh`, such as your terminal. See [verification](verification.md) for recorded results.
