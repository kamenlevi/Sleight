#!/bin/zsh
# Builds Sleight.app from the SwiftPM package and ad-hoc signs it.
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

codesign --force --sign - --identifier com.kamenlevi.sleight "$APP"
echo "Built $APP"
