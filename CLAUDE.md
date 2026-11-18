# Ciel agent rules

`AGENTS.md` is a symlink to this file.

## Verify

- `bash scripts/check.sh` is the full check, and CI runs the same command. It lints scripts, metadata, format and colors, runs the tests with warnings as errors and the search benchmark, then builds the app and runs the native UI, catalog, smoke, performance and window checks. It needs a desktop session. The window check needs Accessibility access for the app that runs the script, such as your terminal. Without it the check is skipped locally and fails CI.
- `bash scripts/check.sh --unit-only` runs everything before the app build and opens no windows.
- `bash scripts/mutants.sh` reapplies each recorded past mistake to a scratch copy and fails if the tests miss one.
- Run tests with `bash scripts/test.sh`, not bare `swift test`. Some Command Line Tools builds omit the Swift Testing macro plugin, and the wrapper loads it.
- Format before checking: `swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift scripts/VerifyUpdate.swift Package.swift`.

## Rules and what enforces them

| Rule | Enforced by |
| --- | --- |
| Saved ids and stored formats never change: entry ids, `WindowAction` raw values, shortcut and placement JSON | `SavedDataTests`, the stored-format fixtures in `LauncherPlacementTests`, mutants M1, M2, M3 and M5 |
| Shortcuts bind under their shipped keys, and a shortcut is saved only after it registers. The one exception: turning on Speech to text saves Right ⌘ for dictation while it waits for access, unless another shortcut has it | `SavedDataTests.aShortcutSavedUnderAShippedKeyFiresItsCommand`, `HotKeysTests`, mutants M12, M13 and M28 |
| A dictation press before the model is ready says why, with the live percent while it downloads, even when Ciel is in the background | `DictationTests.aPressBeforeTheModelIsReadySaysWhy`, the background dictation step of the window check, mutant M27 |
| Unset toggles read as on, under their shipped keys, through `Preferences` | `SavedDataTests.togglesAreOnUntilTurnedOffUnderTheirShippedKeys`, mutant M15 |
| A new `WindowAction` case defines its geometry | The compiler: `unitRect` switches over every case with no `default`. Mutant M4 |
| The bundle id lives only in `AppIdentity` and `Resources/Info.plist` | `SavedDataTests.bundleIdentifierMatchesInfoPlist`, mutant M8 |
| Native checks run only under the checks bundle id, and an unknown flag never launches the app | `LaunchMode` and `LaunchModeTests`, the identity step in `check.sh` (exit 64), mutants M9 and M10 |
| Window commands never target Ciel's own windows | `ForeignProcess` in `WindowController.swift`, `WindowOperationTests.ownProcessIsNeverATarget`, mutant M14 |
| A window command on a full screen window first takes it out of full screen, waits up to 1.5 s for the flag to clear and the frame to hold, then applies on the screen it lands on | `WindowOperationTests.leavesFullScreenFirst` and `fullScreenExitState`, mutant M29 |
| Window settle retries an unchanged window after 0.2 s, matches within 3 pt, settles as constrained only when the retry repeats, and never yields before the window responds | `FrameSettleTests`, `WindowOperationTests`, mutants M16 to M20 |
| An invalidated icon load never delivers and never holds a load slot | `IconCacheTests`, whose waits fail after 3 s instead of hanging, mutants M21 and M22 |
| Onboarding and Settings save a launcher shortcut only after Spotlight lets it go, through the shared `SpotlightGuide`, and read a Spotlight shortcut missing from the saved list as on | `OnboardingTests`, `SettingsSpotlightTests`, the onboarding and Settings Spotlight steps in `SmokeCheck`, mutants M24, M25 and M26 |
| A launcher shortcut that Spotlight holds opens System Settings at Keyboard Shortcuts > Spotlight, and the guide card stays under System Settings until Spotlight lets go or the user cancels | `SettingsSpotlightTests`, `OnboardingTests`, the Spotlight guide step of the window check, mutants M31 and M32 |
| A speech model counts as ready only after its size and SHA-256 match the pinned values | `SpeechModelStoreTests`, mutant M23 |
| Ad-hoc builds sign without hardened runtime. Developer ID builds sign app and framework with hardened runtime, one Team ID and library validation on | The signature check at the end of `scripts/build.sh`, and the launch step in `.github/workflows/checks.yml` |
| `scripts/appcast.sh` writes an appcast only for a signature that matches `SUPublicEDKey`, and `sign_update` output never reaches a log or a `bash -x` trace | The wrong-key and `bash -x` malformed key cases in `scripts/check-appcast.sh` |
| Catalog events match canonical roots, so symlinked folders still update | `CatalogTests`, mutant M11 |
| Tab cycles categories in order, and a window command reports its own title | `LauncherCategoryTests`, `WindowOperationTests`, mutants M6 and M7 |
| Result row icons draw in the colors `ResultCell.mark` sets, selected or not. AppKit's selected-row style never recolors them, and the hover overlay never covers a selected row | `LauncherCellTests.resultIconsDrawInTheirRowColorsSelectedOrNot` and `aHoveredRowSelectedFromTheKeyboardKeepsItsSelectionFill`, mutant M30 |
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
