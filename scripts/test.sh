#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/AirAnki"
export CLANG_MODULE_CACHE_PATH="$PACKAGE/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PACKAGE/.build/module-cache"
export TMPDIR="$ROOT/build/tmp"
mkdir -p "$TMPDIR"
ARGS=(--package-path "$PACKAGE" --disable-sandbox --cache-path "$PACKAGE/.build/cache" --config-path "$PACKAGE/.build/config" --security-path "$PACKAGE/.build/security")
LOG="$ROOT/build/xctest-attempt.log"
if swift test "${ARGS[@]}" "$@" > "$LOG" 2>&1; then
    cat "$LOG"
elif grep -q "no such module 'XCTest'" "$LOG"; then
    echo "XCTest is unavailable in this Command Line Tools installation; running the same tests with AirAnkiCoreSelfTest."
    AIRANKI_SELF_TEST=1 swift run "${ARGS[@]}" -c release AirAnkiCoreSelfTest
else
    cat "$LOG"
    exit 1
fi
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/anki-addon/tests"
