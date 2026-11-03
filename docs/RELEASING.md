# Releasing AirAnki

Build on macOS 14 or later with the Apple Command Line Tools and Python 3.
Xcode and XCTest are not required: the test script falls back to the Swift
self-test runner and then runs the Python add-on tests. The release scripts
use the system `rsync`, `zip`, `lipo`, `codesign`, and `hdiutil` tools.

1. Set the same dotted numeric version in all three places:
   - `Resources/Info.plist`: `CFBundleShortVersionString`.
   - `anki-addon/airanki_bridge/commands.py`: `BRIDGE_VERSION`.
   - `anki-addon/airanki_bridge/manifest.json`: `human_version`.
   Increment `CFBundleVersion` in Info.plist for each released build.
2. Run `./scripts/test.sh` and resolve any failures.
3. Run `./scripts/build_release.sh`.
4. Check the printed architectures and inspect the artifacts:

   ```sh
   lipo -archs build/AirAnki.app/Contents/MacOS/AirAnki
   codesign --verify --strict build/AirAnki.app
   unzip -l dist/AirAnki-Bridge-1.0.0.ankiaddon
   (cd dist && shasum -a 256 -c SHA256SUMS.txt)
   hdiutil verify dist/AirAnki-1.0.0.dmg
   ```

Replace `1.0.0` in the checks with the release version. The add-on archive must
contain `__init__.py` and `manifest.json` at its root, with no enclosing
`airanki_bridge` directory. Neither the archive nor the bundled add-on should
contain `__pycache__`, `tests`, `meta.json`, or `.DS_Store`.

The script attempts a universal arm64 + x86_64 build. If the Intel compilation
fails, it prints a warning and rebuilds arm64 only. Any other failure stops the
release. Check the output before describing a release as supporting Intel Macs.
For a standalone app build, `./scripts/build_app.sh` defaults to the host
architecture; `ARCHS="arm64 x86_64" ./scripts/build_app.sh` explicitly requests
both. That script never silently falls back (exit status 20 identifies an
x86_64 compilation failure).

`dist/` contains the DMG, the companion `.ankiaddon` archive, and
`SHA256SUMS.txt`. The DMG contains AirAnki, an Applications shortcut, and add-on
installation instructions. The app contains the bridge under
`Contents/Resources/AnkiAddon/airanki_bridge`, plus the license and third-party
notices. An icon is included when `Resources/AppIcon.icns` exists.

## Optional Developer ID signing and notarization

By default, builds are ad-hoc signed and are not notarized. For a public
notarized release, use an existing **Developer ID Application** certificate in
your keychain and an existing `notarytool` keychain profile. With both available:

```sh
DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-existing-notarytool-profile' \
./scripts/build_release.sh
```

Only when both variables are nonempty does the script sign the staged app with
hardened runtime and a timestamp, sign the DMG, submit the DMG using
`xcrun notarytool submit --keychain-profile ... --wait`, and staple the accepted
ticket to the DMG. Checksums are written after stapling. A failure stops the
release; it never silently substitutes an ad-hoc release. `build/AirAnki.app`
remains the ad-hoc development build; the signed release app is inside the DMG.

## Gatekeeper and release smoke checks

For unsigned/ad-hoc builds, macOS may require right-click → Open, or System
Settings → Privacy & Security → Open Anyway. Depending on the macOS version,
Open Anyway may be required after the first attempted launch. Do not advise
users to disable Gatekeeper globally.

Before publishing, manually check first-launch add-on installation, Anki
restart, a review session, and login-item behavior on the supported macOS
versions and architectures. Helpers in this release-plumbing branch still need
to be connected to the first-launch UI before the DMG's automatic-installation
instructions describe a complete user flow. Real Anki and system settings are
not exercised by the automated tests. Publishing and uploading are separate
manual steps; the scripts only create local artifacts unless notarization is
explicitly configured.
