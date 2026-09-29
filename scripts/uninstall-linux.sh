#!/usr/bin/env bash
set -euo pipefail
if [ "$EUID" -ne 0 ]; then
  echo "Run this with sudo: sudo ./scripts/uninstall-linux.sh" >&2
  exit 1
fi
systemctl stop grabvoprintping || true
systemctl disable grabvoprintping || true
rm -f /etc/systemd/system/grabvoprintping.service
systemctl daemon-reload
echo "GrabvoPrintPing service removed. Files on disk were left untouched."
