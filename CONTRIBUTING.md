# Contributing to Ciel

Ciel is a small native macOS app. Keep search fast and the interface clear.

Use macOS 14 or later and a Swift 6 toolchain. Install Xcode or Apple's Command Line Tools. Run:

```sh
bash scripts/check.sh
```

Native UI checks use a separate bundle identifier. They do not change your installed Ciel preferences. Use `bash scripts/check.sh --core-only` when you do not need native UI checks. The core checks need no Accessibility access. The optional `--window-test` needs access for its test process and operates only on a temporary test window.

Format Swift changes before running checks:

```sh
swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
```

Use the tokens in `Sources/Ciel/DesignSystem.swift`. Check light and dark appearance. Check Reduce Motion, Reduce Transparency, and Increase Contrast. Keep keyboard input, selection, and resizing immediate. Use native controls when possible.

Explain the problem, the change, and the checks in each pull request. Add a core check when behavior changes. Include a screenshot for interface changes. Do not commit `.build`, `dist`, credentials, personal preferences, or signing certificates.

See [design system](docs/design-system.md) and [release guide](docs/releasing.md).
