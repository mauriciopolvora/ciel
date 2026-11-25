# Ciel

Ciel is a native macOS launcher for apps, window commands and speech to text, in Swift 6 and AppKit. People install it from the GitHub releases, and the site in `site/` links to them.

This file stays under 4 KB, and `CLAUDE.md` is a symlink to it. A rule that a machine can check goes in a lint, a test or a CI check, not here. [docs/rules.md](docs/rules.md) pairs each repository rule with what enforces it.

## Layout

- `Sources/CielCore`: search, ranking, usage history, speech and window geometry, with no AppKit. `Sources/Ciel`: the app, by feature. `Sources/CielMain`: the entry point. `Sources/CielBenchmarks`: the search benchmark.
- `Tests`: Swift Testing suites. `scripts`: build, release and checks. `site`: the website, a Cloudflare Worker. `docs`: design, artwork and release notes, and the rules table.

## Checks

- `git config core.hooksPath .githooks` turns on the hooks once per clone. `pre-commit` runs gitleaks on staged changes. `pre-push` runs `scripts/check-fast.sh`, the comment lint on each pushed tip, then `scripts/lint/check-commits.sh` and gitleaks on pushed commits. Both fail without gitleaks. Never use `--no-verify`.
- `bash scripts/check-fast.sh` runs every check that needs no macOS and lists each failure. Agent hosts run Linux, so the Swift build, tests, format and mutants run only in CI.
- `bash scripts/check.sh` is the full check, and CI (`.github/workflows/checks.yml`) runs it on macOS. `--unit-only` stops before the app build. The window check needs Accessibility access for the app that runs it.
- Format first: `swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift scripts/release/GenerateDMGBackground.swift scripts/release/VerifyUpdate.swift Package.swift`. Run tests with `bash scripts/test.sh`, not bare `swift test`.
- Never rerun a failed CI job to get it green. Reproduce the failure, then fix it.

## Verify

Read `.agents/skills/verify-ciel/SKILL.md` before you prove a change in the app. `bash .agents/skills/verify-ciel/scripts/ciel-verify.sh journey all` drives a copy of `dist/Ciel.app` the way a user does, and CI runs it after the build. A window or utility command with no recipe fails `VerifyRecipeTests`.

## Deploy

- Releases ship by hand through `.github/workflows/release.yml` from main. It needs a passed `Check Ciel` push run on the commit it releases. `docs/releasing.md` has the steps.
- The site deploys by hand: `bun run deploy` in `site/` checks the download links, writes the latest release version, then runs `cf deploy`.

## Judgment rules

Nothing checks these, so read them before you start.

- **Minimal black UI.** No chrome, no color beyond the gray tokens, and no added text, counts, hints, tabs or controls unless the operator asks. The brief is in `docs/design-system.md`. Past failure: filter tabs, a branding footer and "soft sky colors", each rejected with "minimal clean style" and "make it black".
- **Window access after a rebuild.** An ad-hoc rebuild or install gets a new code identity. macOS still shows Ciel as enabled, but `AXIsProcessTrusted()` returns false and window commands fail. After any rebuild or install, run a window command on the installed app before you report done. If access is gone, tell the operator to re-grant it (README, Window commands). Never run `tccutil`.
- **Public claims go in the ledger.** A new sentence in the README, the site or the docs about network use, build architecture, full screen handling, Spaces or dictated audio gets a line in `scripts/lint/claims.txt`. The lint protects only the claims listed there.
- **Window timing is not instant.** Apps apply frames late, clamp sizes and animate minimize. Change the settle timing in `FrameSettle` or `WindowOperationEngine` only with a full `check.sh` run whose window check passed, not skipped.

## When the operator corrects you

Fix the mistake, then add a row to `docs/rules.md`. If the rule was already a judgment rule here, that is a repeat: encode it as a type, test, lint or mutant in the same change, name the enforcer in its row, and drop it from this file.
