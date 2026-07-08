#!/bin/zsh
# Builds Sleight.app from the SwiftPM package and signs it. Uses the stable
# "Sleight Local Signing" identity when present (scripts/make-identity.sh)
# so permission grants survive updates; falls back to ad-hoc otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Sleight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Sleight "$APP/Contents/MacOS/Sleight"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [[ -f assets/AppIcon.icns ]]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "Sleight Local Signing"; then
  IDENTITY="Sleight Local Signing"
fi
codesign --force --sign "$IDENTITY" --identifier com.kamenlevi.sleight "$APP"
echo "Built $APP (signed: $IDENTITY)"
