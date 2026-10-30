# Ciel agent rules

`AGENTS.md` is a symlink to this file.

## Verify

- `bash scripts/check.sh` is the full check, and CI runs the same command. It lints scripts, metadata, format and colors, runs the tests with warnings as errors and the search benchmark, then builds the app and runs the native UI, catalog, smoke, performance and window checks. It needs a desktop session. The window check needs Accessibility access for the app that runs the script, such as your terminal. Without it the check is skipped locally and fails CI.
- `bash scripts/check.sh --unit-only` runs everything before the app build and opens no windows.
- `bash scripts/mutants.sh` reapplies each recorded past mistake to a scratch copy and fails if the tests miss one.
- Run tests with `bash scripts/test.sh`, not bare `swift test`. Some Command Line Tools builds omit the Swift Testing macro plugin, and the wrapper loads it.
- Format before checking: `swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift Package.swift`.

## Rules and what enforces them

| Rule | Enforced by |
| --- | --- |
| Saved ids and stored formats never change: entry ids, `WindowAction` raw values, shortcut and placement JSON | `SavedDataTests`, the stored-format fixtures in `LauncherPlacementTests`, mutants M1, M2, M3 and M5 |
| Shortcuts bind under their shipped keys, and a shortcut is saved only after it registers | `SavedDataTests.aShortcutSavedUnderAShippedKeyFiresItsCommand`, `HotKeysTests`, mutants M12 and M13 |
| Unset toggles read as on, under their shipped keys, through `Preferences` | `SavedDataTests.togglesAreOnUntilTurnedOffUnderTheirShippedKeys`, mutant M15 |
| A new `WindowAction` case defines its geometry | The compiler: `unitRect` switches over every case with no `default`. Mutant M4 |
| The bundle id lives only in `AppIdentity` and `Resources/Info.plist` | `SavedDataTests.bundleIdentifierMatchesInfoPlist`, mutant M8 |
| Native checks run only under the checks bundle id, and an unknown flag never launches the app | `LaunchMode` and `LaunchModeTests`, the identity step in `check.sh` (exit 64), mutants M9 and M10 |
| Window commands never target Ciel's own windows | `ForeignProcess` in `WindowController.swift`, `WindowOperationTests.ownProcessIsNeverATarget`, mutant M14 |
| Window settle retries an unchanged window after 0.2 s, matches within 3 pt, settles as constrained only when the retry repeats, and never yields before the window responds | `FrameSettleTests`, `WindowOperationTests`, mutants M16 to M20 |
| An invalidated icon load never delivers and never holds a load slot | `IconCacheTests`, whose waits fail after 3 s instead of hanging, mutants M21 and M22 |
| A speech model counts as ready only after its size and SHA-256 match the pinned values | `SpeechModelStoreTests`, mutant M23 |
| Catalog events match canonical roots, so symlinked folders still update | `CatalogTests`, mutant M11 |
| Tab cycles categories in order, and a window command reports its own title | `LauncherCategoryTests`, `WindowOperationTests`, mutants M6 and M7 |
| Colors, labels, switches and the About panel come from `Sources/Ciel/DesignSystem.swift` | `scripts/lint-colors.sh` in `check.sh`. Its error names the token to use |
| Native behavior works in the real app, not only in fakes | The native modes in `check.sh`, which CI runs on macOS with the window check required |
| Concurrency is checked, never silenced | Swift 6 language mode in `Package.swift`, and `check.sh` builds with warnings as errors |
| A mutant follows the code it targets when you move or change that code | `mutants.sh` fails with `<id> no longer applies to <file>`, in its own CI job |

## Judgment rules

Nothing checks these, so read them before you start.

- **Minimal black UI.** No chrome, no color beyond the gray tokens, and no added text, counts, hints, tabs or controls unless the operator asks. The brief is in `docs/design-system.md`. Past failure: filter tabs, a branding footer and "soft sky colors", each rejected with "minimal clean style" and "make it black".
- **Window access after a rebuild.** An ad-hoc rebuild or install gets a new code identity. macOS still shows Ciel as enabled, but `AXIsProcessTrusted()` returns false and window commands fail. The app then warns once through the HUD at launch. After any rebuild or install, run a window command on the installed app before you report done. If access is gone, tell the operator to re-grant it (README, Window commands). Never run `tccutil`.
- **Window timing is not instant.** Apps apply frames late, clamp sizes and animate minimize. Change the settle timing in `FrameSettle` or `WindowOperationEngine` only with a full `check.sh` run whose window check passed, not skipped.

## When the operator corrects you

Fix the mistake, then add the rule here. If the rule was already here with nothing enforcing it, that is a repeat: encode it as a type, test, lint or mutant in the same change and name the enforcer in the table. Drop a rule once its mistake can no longer happen.
