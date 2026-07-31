#!/bin/bash
# Installs the Sleight wake helper. Runs as root, invoked by the app.
# Usage: install-helper.sh <app-resources-dir> <console-user>
set -euo pipefail

RESOURCES="$1"
CONSOLE_USER="$2"
LABEL="com.kamenlevi.sleight.helper"
BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CONFIG_DIR="/Library/Application Support/Sleight"
LOG_DIR="/Library/Logs/Sleight"

# Stop any previous version before replacing it.
launchctl bootout "system/$LABEL" 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools "$LOG_DIR"
install -m 755 -o root -g wheel "$RESOURCES/sleight-helper" "$BIN"
install -m 644 -o root -g wheel "$RESOURCES/$LABEL.plist" "$PLIST"

# The schedule directory belongs to the user running Sleight, so the app can
# rewrite the times whenever automations change without asking for a password
# every time. All the helper ever reads from it is clock times and weekdays.
mkdir -p "$CONFIG_DIR"
chown "$CONSOLE_USER" "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

launchctl bootstrap system "$PLIST"
echo "Sleight wake helper installed"
