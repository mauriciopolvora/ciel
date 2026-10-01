# Architecture verification

Checked on 1 October 2026 on Apple silicon with macOS 27 and Swift 6.4. The deployment target remains macOS 14. This records the architecture changes in source. The installed app remains version 0.4.2, build 10.

## Source and native checks

Run `bash scripts/check.sh` for the full local check. It creates a diagnostic app with a separate bundle identifier and catalog cache. Run `bash scripts/check.sh --unit-only` without opening windows. The optional `--window-test` requires Accessibility access for its process and uses only temporary test windows.

| Check | Result |
| --- | --- |
| Swift format, shell syntax, and Info.plist | Passed |
| Swift 6 language mode | Passed; compiler warnings treated as errors in unit checks |
| Discovered Swift Testing tests | 89 passed: 30 core and 59 app tests |
| Window adapter and operation engine | 21 deterministic tests passed |
| Async icon cache and cell reuse | Cache limits, coalescing, stale completion, and invalidation tests passed |
| Catalog | Unchanged cache writes and publications suppressed; empty/cache-equal completion and event classification passed |
| Real filesystem events | Five checks passed: empty completion, nested addition, metadata update, icon-only invalidation, removal |
| Native launcher | 240 query/category changes passed; blank input, native selection, panel sizing, and retained cells passed |
| Native help | Real Window Shortcuts menu action and Keyboard Guide passed; screenshots captured |
| Native window fixture | 12 checks passed on two displays, including minimize and minimum-size handling |
| Normal launcher Accessibility hierarchy | Remote `AXWindows` contains an `AXWindow` |
| Universal app | arm64 and x86_64 compiled; strict ad-hoc signature passed |
| Runtime dependencies | App binary links system libraries; no workspace framework is required |

GitHub CI runs the unit tests, release search budgets, universal build, signature checks, and artifact upload. Results are available in [GitHub Actions](https://github.com/mauriciopolvora/ciel/actions).

The local Command Line Tools linker reports missing optional search directories. These are toolchain diagnostics. Swift source checks pass with compiler warnings treated as errors.

## Performance measurements

The release search benchmark covers 12 query cases at each catalog size. Three warmup searches precede 20 measured searches for each case. Reports are saved under `.build/performance` and uploaded by CI.

| Catalog | Observed p95 range |
| --- | --- |
| 1,018 entries | 1.04–4.41 ms |
| 10,018 entries | 10.60–42.28 ms |

The release native diagnostic used 300 query changes and 5.22 idle seconds. Its catalog contained 111 apps, 18 window commands, and two utility entries.

| Native measurement | Result |
| --- | --- |
| App entry to catalog and panel readiness | 174.65 ms |
| First query layout/display submission | 6.14 ms |
| First query icon settlement | 11.94 ms |
| Repeated update median / p95 / maximum | 1.26 / 3.27 / 4.66 ms |
| Idle CPU, as a percentage of one core | 0.35% |
| Resident growth across this session | 8.11 MiB |

All configured budgets passed. A forced low native update budget returned exit 1 and wrote a failing JSON report. Forced absolute and baseline search failures also returned exit 1. Invalid benchmark arguments returned exit 2.

These timings measure the search engine or synchronous layout and drawing submission. They do not measure physical keypress-to-screen latency. Startup begins at the app entry point and excludes the OS loader. Icon settlement includes diagnostic polling overhead. The short idle and memory samples describe this workload. They do not prove long-run resource behavior. The previous mixed benchmark used different queries and cannot establish a percentage improvement for this release benchmark.

## Window behavior

The operation engine shares one 500 ms frame budget across writes, polling, retries, and visibility corrections. Minimize uses a one-second budget. A temporary AX state-read failure during the Dock animation retries within that budget. Permanent errors return immediately. Fast updates retain the size-position-size burst without an intermediate wait.

The final universal app passed the native fixture. Same-display frame commands completed in 2–9 ms. Moving to the next display completed in 5 ms. Restore across displays completed in 153 ms. A minimum-size command completed in 284 ms and kept the window within the usable display.

Synchronous Accessibility IPC cannot be cancelled after dispatch. Each normal message has a timeout of at most 250 ms, reduced to the remaining operation budget. Enhanced UI restoration gets a separate best-effort 50 ms cleanup timeout. Repeated stable constrained frames permit early completion. An app can still defer its final frame after a long stable intermediate frame.

Enhanced UI restoration passed injected success and error tests. The real AppKit fixture does not support `AXEnhancedUserInterface`, so its native check is skipped. The window fixture starts before resident app services and retains its native window owner for the complete event loop.

## Installed app and distribution

The architecture work builds `dist/Ciel.app`. It does not install a replacement or change the installed app's Accessibility grant. Saved shortcuts, usage history, menu icon preference, display placement, and the production bundle identifier remain compatible.

Earlier installed-app checks covered blank input, typed results, app launch, the global shortcut, drag placement, snapping, native text selection, saved placement after restart, readable About text, and the menu icon setting.

Remaining coverage:

- Developer ID signing, notarization, and clean-Mac Gatekeeper acceptance.
- Intel and macOS 14 runtime checks. Both architectures compile.
- Launcher dragging across displays.
- Launch at login after logout or reboot.
- Full manual coverage of Reduce Motion, Reduce Transparency, and Increase Contrast.
- Enhanced UI restoration in a real app that supports that attribute.
- Physical input-to-display latency and long-run resource behavior.

See the [architecture plan](architecture-plan.md) for repeatable diagnostics and the [release guide](releasing.md) for signed distribution.
