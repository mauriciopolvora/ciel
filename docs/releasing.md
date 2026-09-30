# Release Ciel

## Release status

Ciel 0.4.2 is prepared for local use. The local app is ad-hoc signed. It is not a notarized public release. Source is published at [mauriciopolvora/ciel](https://github.com/mauriciopolvora/ciel) under the MIT license. A notarized download is not available yet.

The workflow in `.github/workflows/checks.yml` checks the core, builds a universal app, verifies its signature, and uploads a development archive. It does not sign with Developer ID or publish a release. See [GitHub Actions](https://github.com/mauriciopolvora/ciel/actions) for hosted build results.

## Build architectures

```sh
CIEL_ARCH=universal bash scripts/build.sh
```

The universal app contains arm64 and x86_64. `CIEL_ARCH` also accepts `native`, `arm64`, or `x86_64`. Universal compilation does not prove runtime behavior on Intel. Test the app on each supported platform before release.

## Sign and notarize

Install a **Developer ID Application** certificate and its private key in the macOS keychain. Create a `notarytool` keychain profile with Apple's notarization credentials. Keep credentials and certificates outside the repository.

Run:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='ciel-notary' \
bash scripts/release.sh
```

The release script builds a universal app with hardened runtime and a secure timestamp. It submits the archive to Apple's notarization service and waits for the result. It then staples and validates the ticket, checks Gatekeeper acceptance, creates a fresh ZIP, and writes a SHA-256 checksum. A failed step stops the script.

The final files are `dist/Ciel-0.4.2-universal.zip` and its `.sha256` file. Review the signed app before uploading these files to a release. The release script does not publish or create a repository.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [notarytool guidance](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

## Check the release

1. Run `bash scripts/check.sh` with other launcher copies closed.
2. Run the optional `--window-test` from an authorized process.
3. Install the exact signed bundle in Applications and open it through Finder.
4. Check global shortcut, app launch, settings, category control, and window commands in everyday apps.
5. Check login behavior after logout or reboot. Check light and dark appearance and macOS accessibility display settings.
6. Download the release on a clean Mac. Verify Gatekeeper acceptance and the checksum.
7. Check macOS 14 and Intel runtime behavior. Do not treat cross-compilation as those checks.

## Upgrade identity

The display name and executable are Ciel. The bundle identifier remains `app.mauriciopolvora.jumpstart`. This preserves saved shortcuts and launch history from Jumpstart. Keep this identifier stable in future releases.

Ad-hoc signatures change identity when code changes. If window access stops working after a local rebuild, re-authorize the installed Ciel app in macOS privacy settings. Do not use a broad bundle-identifier-only signing requirement. Use the same valid signing certificate for future public updates.

The install script saves old Ciel or Jumpstart bundles under `.build/backups` before replacing them. For rollback, quit Ciel and copy the saved bundle back to `~/Applications`. Avoid running two copies with the same bundle identifier.

Ciel 0.4.2 has no automatic update service. Updates require a manual download or build and installation.
