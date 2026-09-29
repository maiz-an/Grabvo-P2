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
echo "Trusting the agent's self-signed certificate on THIS Mac (so Chrome/Safari here never shows a warning for it — you'll be asked for your password)..."
CERT_PATH="$INSTALL_DIR/certs/agent-cert.pem"
waited=0
while [ ! -f "$CERT_PATH" ] && [ "$waited" -lt 15 ]; do
  sleep 1
  waited=$((waited + 1))
done
if [ -f "$CERT_PATH" ]; then
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_PATH" \
    && echo "Certificate trusted system-wide on this Mac." \
    || echo "Could not add the certificate automatically — trust it manually via Keychain Access (System keychain, set to 'Always Trust')."
else
  echo "Certificate wasn't generated yet (agent may still be starting) — re-run this script, or trust $CERT_PATH manually once it exists."
fi

echo ""
echo "GrabvoPrintPing installed as a launchd agent (starts at login)."
echo "Logs:  tail -f \"$INSTALL_DIR/grabvoprintping.log\""
echo "Stop:  launchctl unload \"$PLIST_DEST\""
echo ""
echo "Other devices (phones) still need to install the certificate once -"
echo "point their browser at http://THIS-MAC-IP:8766/cert to download it,"
echo "then install it as a trusted certificate (see README.md)."
