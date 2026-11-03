#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/AirAnki"
export CLANG_MODULE_CACHE_PATH="$PACKAGE/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PACKAGE/.build/module-cache"
export TMPDIR="$ROOT/build/tmp"
mkdir -p "$TMPDIR"
ARGS=(--package-path "$PACKAGE" --disable-sandbox --cache-path "$PACKAGE/.build/cache" --config-path "$PACKAGE/.build/config" --security-path "$PACKAGE/.build/security")
read -r -a ARCH_LIST <<< "${ARCHS:-$(uname -m)}"
if [ "${#ARCH_LIST[@]}" -eq 0 ]; then
    echo "ARCHS must contain arm64 and/or x86_64." >&2
    exit 1
fi
BINARIES=()
for arch in "${ARCH_LIST[@]}"; do
    case "$arch" in
        arm64|x86_64) ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    TARGET_ARGS=(--triple "$arch-apple-macosx14.0" --build-path "$PACKAGE/.build/release-$arch")
    echo "Building AirAnki for $arch..."
    if swift build "${ARGS[@]}" "${TARGET_ARGS[@]}" -c release --product AirAnki; then
        BIN_DIR="$(swift build "${ARGS[@]}" "${TARGET_ARGS[@]}" -c release --show-bin-path)"
        BINARIES+=("$BIN_DIR/AirAnki")
    else
        echo "ERROR: AirAnki build failed for $arch." >&2
        # build_release.sh may fall back only after an Intel compilation failure.
        if [ "$arch" = x86_64 ]; then exit 20; fi
        exit 1
    fi
done
STAGING="$(mktemp -d "$ROOT/build/app.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/AirAnki.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/AnkiAddon/airanki_bridge"
if [ "${#BINARIES[@]}" -gt 1 ]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/AirAnki"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/AirAnki"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
rsync -a --exclude='__pycache__' --exclude='tests' --exclude='meta.json' --exclude='.DS_Store' \
    "$ROOT/anki-addon/airanki_bridge/" "$APP/Contents/Resources/AnkiAddon/airanki_bridge/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/AnkiAddon/airanki_bridge/LICENSE"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
rm -rf "$ROOT/build/AirAnki.app"
mv "$APP" "$ROOT/build/AirAnki.app"
echo "Built $ROOT/build/AirAnki.app ($(lipo -archs "$ROOT/build/AirAnki.app/Contents/MacOS/AirAnki"))"
