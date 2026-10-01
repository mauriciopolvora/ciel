# Local usage history

The launcher records successful app launches and window commands. It records only actions run through the launcher. It saves a use count and last-used time in the existing `app.mauriciopolvora.jumpstart` preferences domain. It does not use a server, AI model, or background activity monitor.

The search engine ranks apps and window commands together by use count. Recent use breaks ties. Typed queries keep strong text matches ahead of history. The interface shows results only for a nonempty query. The empty launcher does not display usage suggestions. Existing counts remain valid after the update. No settings page or database is required.

Minimize is included in the command catalog. macOS can accept the Accessibility change before the Dock animation updates the minimized state. The controller confirms the state on its background window queue, with a one-second limit, before it records success.

## Checks

The unit tests cover app and command ranking, recent-use ties, exact text priority, saved history, and preservation of old counts. Run `bash scripts/check.sh --unit-only`.

The optional native window fixture checks geometry, restore, display movement, and minimize. It needs Accessibility access for its own test process. See [verification](verification.md) for recorded results.
