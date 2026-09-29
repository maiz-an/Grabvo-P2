#!/usr/bin/env bash
# One-click installer for macOS/Linux: installs Node.js if missing,
# downloads GrabvoPrintPing, builds it, and registers it as a
# background service (systemd on Linux, launchd on macOS).
#
# Usage (once hosted, e.g. at qz.grabvo.app):
#   curl -fsSL https://qz.grabvo.app/install-grabvoprintping.sh | bash
#
# Or run this file directly after downloading it.
set -euo pipefail

DOWNLOAD_URL="${GRABVO_DOWNLOAD_URL:-https://qz.grabvo.app/downloads/GrabvoPrintPing.zip}"
INSTALL_DIR="${GRABVO_INSTALL_DIR:-$HOME/GrabvoPrintPing}"

echo "=========================================="
echo " GrabvoPrintPing Setup"
echo "=========================================="

OS="$(uname -s)"

install_node_linux() {
  if command -v node >/dev/null 2>&1; then
    echo "Node.js already installed - skipping."
    return
  fi
  echo "Installing Node.js..."
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo dnf install -y nodejs
  elif command -v yum >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo yum install -y nodejs
  else
    echo "Could not detect apt/dnf/yum. Install Node.js 18+ manually: https://nodejs.org" >&2
    exit 1
  fi
}

install_node_macos() {
  if command -v node >/dev/null 2>&1; then
    echo "Node.js already installed - skipping."
    return
  fi
  echo "Installing Node.js..."
  if command -v brew >/dev/null 2>&1; then
    brew install node
  else
    echo "Homebrew not found. Install it from https://brew.sh, or install Node.js 18+ manually from https://nodejs.org, then re-run this script." >&2
    exit 1
  fi
}

case "$OS" in
  Linux) install_node_linux ;;
  Darwin) install_node_macos ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

echo ""
echo "Downloading GrabvoPrintPing..."
WORK_DIR="$(mktemp -d)"
curl -fsSL "$DOWNLOAD_URL" -o "$WORK_DIR/GrabvoPrintPing.zip"
unzip -oq "$WORK_DIR/GrabvoPrintPing.zip" -d "$WORK_DIR/extract"

# The zip may contain a single top-level "GrabvoPrintPing" folder -
# flatten that into the real install dir either way.
SRC_DIR="$WORK_DIR/extract"
if [ -d "$WORK_DIR/extract/GrabvoPrintPing" ]; then
  SRC_DIR="$WORK_DIR/extract/GrabvoPrintPing"
fi

mkdir -p "$INSTALL_DIR"
cp -R "$SRC_DIR"/. "$INSTALL_DIR"/
rm -rf "$WORK_DIR"

echo "Installed to $INSTALL_DIR"

cd "$INSTALL_DIR"
[ -f .env ] || { [ -f .env.example ] && cp .env.example .env; }

echo ""
echo "Installing dependencies and building..."
npm install --omit=dev
npm run build

chmod +x scripts/*.sh

echo ""
if [ "$OS" = "Linux" ]; then
  echo "Registering the systemd service (you may be asked for your password)..."
  sudo ./scripts/install-linux.sh
else
  echo "Registering the launchd service..."
  ./scripts/install-macos.sh
fi

echo ""
echo "=========================================="
echo " SETUP COMPLETE"
echo "=========================================="
echo "GrabvoPrintPing is installed and running."
echo "Check it from another device on this network: http://THIS-MACHINE-IP:8765/status"
