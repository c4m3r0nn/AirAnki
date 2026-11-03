#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release version in Info.plist: $VERSION" >&2
    exit 1
fi
if ARCHS="arm64 x86_64" "$ROOT/scripts/build_app.sh"; then
    echo "Universal arm64 + x86_64 build succeeded."
else
    status=$?
    if [ "$status" -ne 20 ]; then
        echo "Release stopped: app build failed (status $status)." >&2
        exit "$status"
    fi
    echo "WARNING: x86_64 compilation failed; rebuilding this release for arm64 only." >&2
    ARCHS=arm64 "$ROOT/scripts/build_app.sh"
fi
WORK="$(mktemp -d "$ROOT/build/release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGING="$WORK/dmg"
OUTPUT="$WORK/output"
mkdir -p "$STAGING" "$OUTPUT" "$ROOT/dist"
ditto "$ROOT/build/AirAnki.app" "$STAGING/AirAnki.app"
APP="$STAGING/AirAnki.app"
NOTARIZE=false
# notarytool can exit 0 for a rejected submission; require an explicit Accepted status.
notarize() {
    local log="$WORK/notary.log"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$log"
    if ! grep -q "status: Accepted" "$log"; then
        id="$(awk '/^  id:/ {print $2; exit}' "$log")"
        echo "Notarization failed for $1." >&2
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
}
if [ -n "${NOTARY_PROFILE:-}" ] && [ -n "${DEVELOPER_ID:-}" ]; then
    NOTARIZE=true
    codesign --force --options runtime --timestamp -s "$DEVELOPER_ID" "$APP"
    # Notarize and staple the app itself so it passes Gatekeeper offline after leaving the DMG.
    ditto -c -k --keepParent "$APP" "$WORK/AirAnki-notarize.zip"
    notarize "$WORK/AirAnki-notarize.zip"
    xcrun stapler staple "$APP"
else
    codesign --force --sign - "$APP"
    echo "Using ad-hoc signing; this release will not be notarized."
fi
codesign --verify --strict "$APP"
ln -s /Applications "$STAGING/Applications"
printf 'AirAnki installs its Anki add-on for you on first launch. If you prefer, double-click AirAnki-Bridge-%s.ankiaddon.\n' "$VERSION" > "$STAGING/Install the Anki add-on.txt"
ADDON="AirAnki-Bridge-$VERSION.ankiaddon"
DMG="AirAnki-$VERSION.dmg"
(
    cd "$APP/Contents/Resources/AnkiAddon/airanki_bridge"
    zip -q -r "$OUTPUT/$ADDON" . -x '*/__pycache__/*' '__pycache__/*' '*/tests/*' 'tests/*' '*/meta.json' 'meta.json' '*/.DS_Store' '.DS_Store'
)
hdiutil create -volname AirAnki -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT/$DMG"
if [ "$NOTARIZE" = true ]; then
    codesign --force --timestamp -s "$DEVELOPER_ID" "$OUTPUT/$DMG"
    notarize "$OUTPUT/$DMG"
    xcrun stapler staple "$OUTPUT/$DMG"
fi
(
    cd "$OUTPUT"
    shasum -a 256 "$DMG" "$ADDON" > SHA256SUMS.txt
)
for artifact in "$DMG" "$ADDON" SHA256SUMS.txt; do
    mv -f "$OUTPUT/$artifact" "$ROOT/dist/$artifact"
done
echo "Release artifacts in $ROOT/dist ($(lipo -archs "$APP/Contents/MacOS/AirAnki"))"
