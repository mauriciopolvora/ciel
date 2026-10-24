# Contributing to Ciel

Ciel is a small native macOS app. Keep search fast and the interface clear.

Use macOS 14 or later and a Swift 6 toolchain. Install Xcode or Apple's Command Line Tools. Run:

```sh
bash scripts/check.sh
```

Native UI checks run only under a separate bundle identifier. They do not change your installed Ciel preferences. Use `bash scripts/check.sh --unit-only` when you do not need native UI checks. Unit tests need no Accessibility access. The window check moves only temporary test windows. It needs Accessibility access for the app that runs `check.sh`, such as your terminal. Without access it is skipped locally, and CI fails.

Use `bash scripts/test.sh -c release` to run the discovered Swift Testing tests. This wrapper also handles the missing macro registration in some Command Line Tools builds. It uses the toolchain's bundled library. It does not change the selected toolchain. Normal Xcode toolchains run `swift test` without extra flags.

`bash scripts/mutants.sh` reapplies each recorded past mistake to a temporary copy of the repo and fails if the tests miss one. CI runs it on every pull request. When you move or change code that a mutant targets, update that mutant in the script.

Format Swift changes before running checks:

```sh
swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
```

Use the tokens in `Sources/Ciel/DesignSystem.swift`. Check light and dark appearance. Check Reduce Motion, Reduce Transparency, and Increase Contrast. Keep keyboard input, selection, and resizing immediate. Use native controls when possible.

Keep AppKit state on the main actor. Keep blocking filesystem and Accessibility work on their worker executors. Pass immutable values across boundaries. The package uses Swift 6 language mode. Do not disable concurrency checking to resolve an ownership problem.

Explain the problem, the change, and the checks in each pull request. Add a test when a behavior change needs regression coverage. Include a screenshot for interface changes. Do not commit `.build`, `dist`, credentials, personal preferences, or signing certificates.

See the [architecture plan](docs/architecture-plan.md), [design system](docs/design-system.md), and [release guide](docs/releasing.md).
