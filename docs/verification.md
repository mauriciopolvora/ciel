# Ciel 0.4.2 verification

Checked on 30 September 2026 on Apple silicon with macOS 27 and Swift 6.4. The deployment target is macOS 14.

## Source checks

Run `bash scripts/check.sh` for the full local check. Native checks use a separate bundle identifier so they do not change the installed app's preferences. Run `bash scripts/check.sh --core-only` to check the source without opening windows.

| Check | Result |
| --- | --- |
| Swift format, shell syntax, and Info.plist | Passed |
| Search, history, discovery, geometry, and placement | 30 checks passed; zero failures |
| Mixed search benchmark | 1,018 entries; median 0.64 ms, p95 0.82 ms |
| Native launcher | 240 query/category changes passed; row count and panel size correct |
| Empty input | Focused editor, no placeholder, no rows, no empty execution |
| Clearing, whitespace, and catalog refresh | Keep the launcher blank |
| Native editing | Select All, white caret, and gray selection passed |
| Category control | Cycles All, Apps, and Windows; retains query and focus |
| Filesystem events | Nested app addition, metadata update, and removal passed |
| Native help | Settings, Window Shortcuts, and Keyboard Guide passed |
| Screenshots | Refreshed from native checks with default preferences |

The benchmark measures search-engine time. It does not measure keypress-to-screen latency. GitHub CI runs core checks and builds the universal app. Native UI and Accessibility checks need a local desktop session. Hosted results are available in [GitHub Actions](https://github.com/mauriciopolvora/ciel/actions).

## Installed app checks

Earlier checks of the installed build verified blank input, typed results, app launch, the global shortcut, drag placement, snapping, text selection, saved placement after restart, readable About text, and hiding and restoring the menu bar icon. The cleanup does not install a replacement app or change its Accessibility grant.

## Window updates

Build 10 sends size-position-size updates without waiting at intermediate frames. It checks the final frame immediately. It uses a bounded retry if an app clamps a change.

For apps with an enabled `AXEnhancedUserInterface` attribute, Ciel temporarily disables that mode and restores it on return, including error paths. This follows the scoped update approach in [Rectangle's AccessibilityElement](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift). The AppKit fixture does not support this attribute, so its restoration check is skipped.

The exact installed build passed 11 geometry and minimize checks on two displays. Checks include negative display coordinates, maximize-to-half transitions, restore, and next-display movement. Its frame commands completed in 1–7 ms. These values measure command completion on the fixture. They do not measure visual latency in every app.

## Distribution coverage

- Developer ID signing, notarization, and clean-Mac Gatekeeper acceptance remain unverified. Local builds use ad-hoc signing.
- Both architectures compile. Intel and macOS 14 runtime checks remain open.
- Launcher dragging across displays remains unverified. Window commands have passed next-display and restore checks on two displays.
- Launch at login after logout or reboot remains unverified.
- Reduce Motion, Reduce Transparency, and Increase Contrast are implemented. Full manual coverage remains open.
- The Enhanced UI restoration branch needs a check in an app that supports that attribute.
- Long-run memory growth and end-to-end input latency are not measured.

See the [release guide](releasing.md) for signed distribution.
