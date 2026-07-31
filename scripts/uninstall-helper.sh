#!/bin/bash
# Removes the Sleight wake helper. Runs as root, invoked by the app.
set -euo pipefail

LABEL="com.kamenlevi.sleight.helper"
BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

# Give back any wake it had booked, so the Mac doesn't keep waking for an
# automation nothing is listening for any more.
[ -x "$BIN" ] && "$BIN" --clear || true

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$BIN"
echo "Sleight wake helper removed"
