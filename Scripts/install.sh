#!/bin/bash
# Builds the `screenshots` tool and links it into ~/.local/bin.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product screenshots
BIN="$(swift build -c release --product screenshots --show-bin-path)/screenshots"

DEST="${HOME}/.local/bin"
mkdir -p "$DEST"
ln -sf "$BIN" "$DEST/screenshots"
echo "Installed: $DEST/screenshots -> $BIN"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "Note: $DEST is not on your PATH. Add this to your shell profile:"
     echo "  export PATH=\"$DEST:\$PATH\"" ;;
esac
