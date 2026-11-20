#!/bin/bash
# Builds the `screenshots` tool and links it into ~/.local/bin.
# Also links the agent skill (skills/ios-screenshots) for every coding agent found on this Mac
# (Claude Code, Codex, OpenCode). Pass --no-skill to skip that.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

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

if [ "${1:-}" != "--no-skill" ]; then
  SKILL="$REPO/skills/ios-screenshots"
  # agent home -> its global skills folder
  for pair in "$HOME/.claude:$HOME/.claude/skills" "$HOME/.codex:$HOME/.codex/skills" "$HOME/.config/opencode:$HOME/.config/opencode/skills"; do
    home="${pair%%:*}"; skills="${pair#*:}"
    [ -d "$home" ] || continue
    mkdir -p "$skills"
    if [ -e "$skills/ios-screenshots" ] && [ ! -L "$skills/ios-screenshots" ]; then
      echo "Skipped: $skills/ios-screenshots exists and is not a link"
      continue
    fi
    ln -sfn "$SKILL" "$skills/ios-screenshots"
    echo "Skill linked: $skills/ios-screenshots"
  done
fi
