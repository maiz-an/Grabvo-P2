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

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "Opening firewall ports (ufw)..."
  ufw allow 8765/tcp >/dev/null || true
  ufw allow 8766/tcp >/dev/null || true
fi

echo ""
echo "Trusting the agent's self-signed certificate on THIS machine (so Chrome/Firefox here never shows a warning for it)..."
CERT_PATH="$INSTALL_DIR/certs/agent-cert.pem"
waited=0
while [ ! -f "$CERT_PATH" ] && [ "$waited" -lt 15 ]; do
  sleep 1
  waited=$((waited + 1))
done
if [ -f "$CERT_PATH" ] && command -v update-ca-certificates >/dev/null 2>&1; then
  cp "$CERT_PATH" /usr/local/share/ca-certificates/grabvoprintping.crt
  update-ca-certificates >/dev/null
  echo "Certificate trusted system-wide on this machine."
elif [ -f "$CERT_PATH" ]; then
  echo "update-ca-certificates not found (non-Debian system) — trust $CERT_PATH manually via your distro's CA tool."
else
  echo "Certificate wasn't generated yet (service may still be starting) — re-run this script, or trust $CERT_PATH manually once it exists."
fi

echo ""
echo "GrabvoPrintPing installed and started as a systemd service."
echo "Status:  systemctl status grabvoprintping"
echo "Logs:    journalctl -u grabvoprintping -f   (or tail -f /var/log/grabvoprintping.log)"
echo "Stop:    sudo systemctl stop grabvoprintping"
echo ""
echo "Other devices (phones) still need to install the certificate once -"
echo "point their browser at http://THIS-MACHINE-IP:8766/cert to download it,"
echo "then install it as a trusted certificate (see README.md)."
