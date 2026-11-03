#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Application Support/Anki2/addons21/airanki_bridge"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
    echo "Refusing to replace non-symlink: $DEST" >&2
    exit 1
fi
mkdir -p "$(dirname "$DEST")"
ln -sfn "$ROOT/anki-addon/airanki_bridge" "$DEST"
echo "AirAnki Bridge linked. Restart Anki to load it."
