# Release Ciel

## Release status

Ciel 0.4.2 is prepared for local use. The local app is ad-hoc signed. It is not a notarized public release. Source is published at [mauriciopolvora/ciel](https://github.com/mauriciopolvora/ciel) under the MIT license. A notarized download is not available yet.

The workflow in `.github/workflows/checks.yml` checks the core, builds an Apple Silicon app, verifies its architecture and signature, and uploads a development archive. It does not sign with Developer ID or publish a release. See [GitHub Actions](https://github.com/mauriciopolvora/ciel/actions) for hosted build results.

## Build architectures

```sh
CIEL_ARCH=arm64 bash scripts/build.sh
```

Ciel runs on Apple Silicon only, because speech to text uses transcribe.cpp with Metal. `CIEL_ARCH` accepts `native` or `arm64`, and the build stops if the app binary is not arm64.

The build copies `CTranscribe.framework` into `Contents/Frameworks`, keeps only its arm64 slice, and removes its headers and module map. It adds the `@executable_path/../Frameworks` rpath to the app binary when SwiftPM did not. It signs the framework first, then the app with `Resources/Ciel.entitlements`, which grants microphone input under the hardened runtime. Developer ID builds use the hardened runtime. Ad-hoc builds do not, because library validation would reject a framework without a Team ID and the app would quit at launch. `codesign --verify --strict --deep` must pass, and the build stops if the app and framework signatures could not load together.

## Sign and notarize

Install a **Developer ID Application** certificate and its private key in the macOS keychain. Create a `notarytool` keychain profile with Apple's notarization credentials. Keep credentials and certificates outside the repository.

Run:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='ciel-notary' \
bash scripts/release.sh
```

The release script builds an Apple Silicon app with hardened runtime and a secure timestamp. It submits the archive to Apple's notarization service and waits for the result. It then staples and validates the ticket, checks Gatekeeper acceptance, creates a fresh ZIP, and writes a SHA-256 checksum. A failed step stops the script.

The final files are `dist/Ciel-0.4.2-arm64.zip` and its `.sha256` file. Review the signed app before uploading these files to a release. The release script does not publish or create a repository.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [notarytool guidance](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

## Check the release

1. Run `bash scripts/check.sh` with other launcher copies closed. It skips the window check without Accessibility access, so also confirm that CI passed on the release commit.
2. Install the exact signed bundle in Applications and open it through Finder.
3. Check global shortcut, app launch, settings, category control, and window commands in everyday apps. Download the speech model, grant microphone access, and dictate into a text field.
4. Check login behavior after logout or reboot. Check light and dark appearance and macOS accessibility display settings.
5. Download the release on a clean Mac. Verify Gatekeeper acceptance and the checksum.
6. Check macOS 14 runtime behavior on an Apple Silicon Mac.

## Upgrade identity

The display name and executable are Ciel. The bundle identifier is `app.mauriciopolvora.ciel`. Saved shortcuts and launch history belong to this identifier. Keep it stable in future releases.

Ad-hoc signatures change identity when code changes. If window access stops working after a local rebuild, re-authorize the installed Ciel app in macOS privacy settings. Do not use a broad bundle-identifier-only signing requirement. Use the same valid signing certificate for future public updates.

The install script saves the old Ciel bundle under `.build/backups` before it replaces it. For rollback, quit Ciel and copy the saved bundle back to `~/Applications`. Avoid running two copies with the same bundle identifier.

Ciel 0.4.2 has no automatic update service. Updates require a manual download or build and installation.
