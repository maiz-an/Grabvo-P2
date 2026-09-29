#!/usr/bin/env bash
# Installs GrabvoPrintPing as a per-user launchd agent (runs at login,
# KeepAlive restarts it if it crashes).
# Usage: ./scripts/install-macos.sh
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="$(command -v node || true)"
PLIST_SRC="$INSTALL_DIR/launchd/app.grabvo.printping.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/app.grabvo.printping.plist"

if [ -z "$NODE_BIN" ]; then
  echo "Node.js 18+ is required and wasn't found on PATH." >&2
  exit 1
fi

echo "Installing dependencies and building..."
cd "$INSTALL_DIR"
npm install --omit=dev
npm run build

if [ ! -f "$INSTALL_DIR/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
  echo "Created .env from .env.example — edit it (PORT, SIGNING_BASE_URL) before relying on this."
fi

mkdir -p "$HOME/Library/LaunchAgents"
sed \
  -e "s#__NODE_BIN__#${NODE_BIN}#g" \
  -e "s#__INSTALL_DIR__#${INSTALL_DIR}#g" \
  "$PLIST_SRC" > "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

echo ""
echo "GrabvoPrintPing installed as a launchd agent (starts at login)."
echo "Logs:  tail -f \"$INSTALL_DIR/grabvoprintping.log\""
echo "Stop:  launchctl unload \"$PLIST_DEST\""
