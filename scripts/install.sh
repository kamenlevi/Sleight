#!/bin/bash
# Sleight one-line installer:
#
#   curl -fsSL https://raw.githubusercontent.com/kamenlevi/Sleight/main/scripts/install.sh | bash
#
# Downloads the latest release and puts Sleight.app into /Applications.
# curl doesn't set the com.apple.quarantine attribute browsers do, so the app
# opens straight away — no "Apple could not verify…" dialog and no trip to
# System Settings for it. Everything runs as you; no sudo. The permissions
# Sleight actually needs (Input Monitoring, Accessibility) are asked for by
# the app itself on first launch.
set -euo pipefail

REPO="kamenlevi/Sleight"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Release archives carry their version in the name, so ask the API which one
# is current rather than guessing at a fixed filename.
echo "Finding the latest release…"
ZIP_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url"[^,]*\.zip"' \
    | head -1 | cut -d'"' -f4)

if [ -z "$ZIP_URL" ]; then
    echo "error: couldn't find a release archive to download." >&2
    echo "GitHub may be rate-limiting anonymous requests. Download it by hand:" >&2
    echo "  https://github.com/$REPO/releases/latest" >&2
    exit 1
fi

echo "Downloading ${ZIP_URL##*/}…"
curl -fsSL "$ZIP_URL" -o "$TMP/Sleight.zip"

ditto -xk "$TMP/Sleight.zip" "$TMP/unpacked"
APP=$(find "$TMP/unpacked" -maxdepth 2 -name "Sleight.app" -print -quit)
if [ -z "$APP" ]; then
    echo "error: Sleight.app not found in the downloaded archive" >&2
    exit 1
fi

# Replace any existing copy (which may be browser-quarantined), quitting a
# running instance first so the swap is clean.
osascript -e 'tell application "Sleight" to quit' >/dev/null 2>&1 || true
pkill -x Sleight 2>/dev/null || true
rm -rf "$DEST/Sleight.app"
ditto "$APP" "$DEST/Sleight.app"

open "$DEST/Sleight.app"
echo "Sleight installed in $DEST and started — look for the dial in your menu bar."
echo "Grant Input Monitoring and Accessibility when asked, then relaunch it:"
echo "  System Settings → Privacy & Security → Input Monitoring / Accessibility"
