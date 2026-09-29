#!/usr/bin/env bash
# Installs GrabvoPrintPing as a systemd service.
# Usage: sudo ./scripts/install-linux.sh
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_USER="${SUDO_USER:-$(whoami)}"
UNIT_SRC="$INSTALL_DIR/systemd/grabvoprintping.service"
UNIT_DEST="/etc/systemd/system/grabvoprintping.service"

if [ "$EUID" -ne 0 ]; then
  echo "Run this with sudo: sudo ./scripts/install-linux.sh" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
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

sed \
  -e "s#__INSTALL_DIR__#${INSTALL_DIR}#g" \
  -e "s#__SERVICE_USER__#${SERVICE_USER}#g" \
  "$UNIT_SRC" > "$UNIT_DEST"

systemctl daemon-reload
systemctl enable grabvoprintping
systemctl restart grabvoprintping

echo ""
echo "GrabvoPrintPing installed and started as a systemd service."
echo "Status:  systemctl status grabvoprintping"
echo "Logs:    journalctl -u grabvoprintping -f   (or tail -f /var/log/grabvoprintping.log)"
echo "Stop:    sudo systemctl stop grabvoprintping"
