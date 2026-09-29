#!/usr/bin/env bash
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/app.grabvo.printping.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "GrabvoPrintPing launchd agent removed. Files on disk were left untouched."
