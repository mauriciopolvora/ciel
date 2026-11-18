# Release Ciel

## Release from GitHub

`.github/workflows/release.yml` publishes a release on a macOS runner. No Mac is needed. To start it:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and merge.
2. Wait for `Check Ciel` to pass on the merge commit.
3. Run the workflow on `main` from the Actions tab, or with `gh workflow run release.yml --ref main -f version=<version>`. It releases the head of `main` and creates the tag `v<version>` on that commit.

Only a manual run on `main` starts a release. A pushed tag does not start it.

To test signing and notarization without a release, run `gh workflow run release.yml --ref main -f version=<current version> -f dry_run=true`. A dry run builds, signs, notarizes and staples, then stops. It creates no tag or release, so it skips the checks for a new version.

Before it reads any secret, the workflow stops unless all of these hold:

- The version matches `CFBundleShortVersionString`, and no release or tag has it yet.
- The commit is on `main`, and the `Check Ciel` workflow passed on it.
- The version is newer than the latest release, and `CFBundleVersion` is higher than the build in the latest appcast, because Sparkle offers only a higher build.
- The app builds.

The workflow then:

1. Imports the Developer ID certificate into a temporary keychain.
2. Writes the update signing key to a temporary file with mode 600.
3. Runs `scripts/release.sh`, which builds, signs, notarizes, staples and writes the seven release files.
4. Creates the release `v<version>` on the exact commit, with all seven files.
5. Downloads `releases/latest/download/Ciel.zip`, `Ciel.dmg`, `appcast.xml` and the versioned zip, and checks that each returns 200 and matches the build byte for byte. It then checks that the appcast lists the version, verifies its EdDSA signature against `SUPublicEDKey`, and checks the downloaded app and disk image with `stapler validate` and Gatekeeper.
6. Deletes the keychain and the key file, also when a step fails.

The job runs in the `release` environment. Only runs from `main` can use it, and admins cannot bypass this rule. Only that environment holds these secrets:

| Secret | Use |
| --- | --- |
| `CIEL_DEVID_P12_BASE64` | Developer ID Application certificate and private key, as a base64 `.p12` |
| `CIEL_DEVID_P12_PASSWORD` | Password of that `.p12` |
| `CIEL_NOTARY_APPLE_ID` | Apple ID for `notarytool` |
| `CIEL_NOTARY_PASSWORD` | App-specific password of that Apple ID |
| `CIEL_NOTARY_TEAM_ID` | Team ID for `notarytool` |
| `CIEL_SPARKLE_ENV` | Contents of `ciel-sparkle.env`, the line `SPARKLE_PRIVATE_ED_KEY=<key>` |

The workflow in `.github/workflows/checks.yml` checks each push. It builds an ad-hoc signed app and uploads it as a development archive. It also builds and checks a development disk image with `scripts/dmg.sh`, opens it in Finder and uploads a screenshot of the window as `Ciel-disk-image-window`. It does not publish anything.

### Roll back

A published release is live as soon as the workflow uploads it, even when the check after it fails. To stop new downloads and updates of a bad release, do one of these:

- `gh release edit v<previous> --latest` points the download link and the appcast back to the previous release. Releases before 0.6.0 have no appcast, so after a rollback to one of them the update feed returns 404 and installed copies find no update.
- `gh release delete v<bad> --cleanup-tag` removes the release and its tag. The workflow refuses to release a version whose release or tag exists, so delete both before you run it again for the same version.

Releases up to 0.6.0 have no `Ciel.dmg`. When either step leaves one of them as the latest release, the site download buttons return 404. Then change the links and the install answer in `site/public/index.html` back to `Ciel.zip` and deploy the site, or publish a fixed release.

Sparkle never offers a lower or equal build, so copies that already updated stay on the bad build. To fix them, release a new version with a `CFBundleVersion` higher than every build ever published. After a rollback, the workflow compares only against the release marked Latest, so it cannot catch a reused build.

## Build architectures

```sh
CIEL_ARCH=arm64 bash scripts/build.sh
```

Ciel runs on Apple Silicon only, because speech to text uses transcribe.cpp with Metal. `CIEL_ARCH` accepts `native` or `arm64`, and the build stops if the app binary is not arm64.

The build copies `CTranscribe.framework` into `Contents/Frameworks`, keeps only its arm64 slice, and removes its headers and module map. It adds the `@executable_path/../Frameworks` rpath to the app binary when SwiftPM did not. It signs the framework first, then the app with `Resources/Ciel.entitlements`, which grants microphone input under the hardened runtime. Developer ID builds use the hardened runtime. Ad-hoc builds do not, because library validation would reject a framework without a Team ID and the app would quit at launch. `codesign --verify --strict --deep` must pass, and the build stops if the app and framework signatures could not load together.

The build also copies `Sparkle.framework` and removes its XPC services, which Sparkle uses only in sandboxed apps. It signs Sparkle's `Autoupdate` and `Updater.app` before the framework, with the same identity and the same Team ID and hardened runtime checks as the rest of the app.

## Sign and notarize on a Mac

Install a **Developer ID Application** certificate and its private key in the macOS keychain. Create a `notarytool` keychain profile with Apple's notarization credentials. Instead of a profile, you can set `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` and `NOTARY_TEAM_ID`, which is what the release workflow does. Keep credentials and certificates outside the repository.

Run:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='ciel-notary' \
bash scripts/release.sh
```

The release script builds an Apple Silicon app with hardened runtime and a secure timestamp. It submits the archive to Apple's notarization service and waits for the result. It then staples and validates the ticket, checks Gatekeeper acceptance, creates a fresh ZIP, and writes a SHA-256 checksum. A failed step stops the script.

After the appcast, it builds the disk image `dist/Ciel.dmg` from the stapled app with `scripts/dmg.sh`. It signs the image with the same Developer ID and a secure timestamp, submits it for notarization a second time, staples and validates the ticket, checks it with `spctl --assess --type open`, and writes `dist/Ciel.dmg.sha256`. So each release makes two notarization submissions: the app, then the disk image.

`scripts/dmg.sh` builds the image with `hdiutil` and Swift only, so no third-party code runs in a release. It draws the background, then copies the app, an `Applications` link and the Finder window layout `Resources/DiskImage.DS_Store` into the image. Before it writes the image, it mounts it read-only at a private mount point and checks that `Ciel.app` passes `codesign --verify --strict --deep` with the same CDHash as the source app, that `Applications` links to `/Applications`, that the background is the picture this build drew and the layout is the committed file, and that nothing else is at the top level. A failed check writes no image, and an image from an earlier build stays as it was.

The layout file holds the window size and the icon positions. To change them, edit the geometry at the top of `scripts/dmg.sh`, run `bash scripts/dmg.sh --layout`, build an image, look at its window in Finder, and commit the new layout file. A build stops when the window size, an icon position, the icon size, the text size or the background reference in the layout file differs from the geometry. Finder finds the background by the volume name, so while another volume named Ciel is mounted, the window shows that volume's background. Only `--layout` needs Python 3.11 or later: it installs `dmgbuild` into `.build/dmg-venv` from the wheel hashes in `scripts/dmg-requirements.txt`. Run it on a Mac that holds no release secrets.

The final files are `dist/Ciel-0.6.1-arm64.zip`, its `.sha256` file, a copy of the same archive named `dist/Ciel.zip` with `dist/Ciel.zip.sha256`, `dist/appcast.xml`, and `dist/Ciel.dmg` with `dist/Ciel.dmg.sha256`. Review the signed app before you publish. The release script does not publish anything. It prints the `gh release create` command that uploads all seven files.

Every GitHub release must use the tag `v<version>`, such as `v0.6.0`, and attach all seven files with these exact names: `Ciel-<version>-arm64.zip`, `Ciel-<version>-arm64.zip.sha256`, `Ciel.zip`, `Ciel.zip.sha256`, `appcast.xml`, `Ciel.dmg` and `Ciel.dmg.sha256`. The site download buttons link to `https://github.com/mauriciopolvora/ciel/releases/latest/download/Ciel.dmg`, so they work only when the latest release has `Ciel.dmg`. Deploy the site only after the first release that has it. `npm run deploy` in `site/` first runs `site/check-downloads.sh`, which stops the deploy unless every `releases/latest/download` link in `site/public/index.html` returns 200. The appcast points installed copies to `https://github.com/mauriciopolvora/ciel/releases/download/v<version>/Ciel-<version>-arm64.zip`, so they update only when that tag and file exist.

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

## Updates

Ciel checks for updates with [Sparkle](https://sparkle-project.org). The app reads the feed at `https://github.com/mauriciopolvora/ciel/releases/latest/download/appcast.xml` and accepts only archives signed by the EdDSA key whose public half is `SUPublicEDKey` in `Resources/Info.plist`.

The release script needs the private key. Copy `~/.config/secrets/ciel-sparkle.env` from mauriciovps to the same path on the Mac, then run `chmod 600` on it. Set `SPARKLE_KEY_FILE` to use another path. The script stops before it builds when the file is missing. Never commit the key. The only copy in GitHub is the `CIEL_SPARKLE_ENV` secret in the `release` environment, which only the release workflow reads.

After it writes `Ciel.zip`, the release script signs the versioned archive and writes `dist/appcast.xml` with `scripts/appcast.sh`. The script checks the signature against `SUPublicEDKey` first, and a key that does not match stops it before it writes the appcast. Attach all seven files to the GitHub release tagged `v<version>`.

CI checks the appcast script with a throwaway key on each run: `scripts/check-appcast.sh` signs a test archive, then validates the XML, its version, length and minimum system fields, and the signature. It also checks that the script refuses a key that does not match `SUPublicEDKey`, and that a malformed key never reaches its output under `bash -x`.

Ciel 0.5.0 and older have no updater. People who installed those versions must download Ciel once by hand. After that, Ciel updates itself.
