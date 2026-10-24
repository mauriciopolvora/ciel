# Local usage history

Ciel records successful app launches from the launcher. It also records successful window commands, from the launcher or from a window shortcut. It saves a use count and last-used time in the `app.mauriciopolvora.ciel` preferences domain. It does not use a server, AI model, or background activity monitor.

Search ranks results by how well they match the typed text. Use count adds a small, capped bonus, so strong text matches stay ahead of history. Recent use breaks ties. The interface shows results only for a query with searchable text. The empty launcher does not display usage suggestions. No settings page or database is required.

Minimize is included in the command catalog. macOS can accept the Accessibility change before the Dock animation updates the minimized state. The controller confirms the state on its background window queue, with a one-second limit, before it records success.

## Checks

The unit tests cover history ranking, recent-use ties, empty queries, exact text priority, saved history, and preservation of old counts. Run `bash scripts/check.sh --unit-only`.

The native window check in `bash scripts/check.sh` covers geometry, restore, display movement, and minimize. It needs Accessibility access for the app that runs `check.sh`, such as your terminal. See [verification](verification.md) for recorded results.
