#!/bin/zsh
# Builds Sleight.app from the SwiftPM package and signs it. Uses the stable
# "Sleight Local Signing" identity when present (scripts/make-identity.sh)
# so permission grants survive updates; falls back to ad-hoc otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal: Apple Silicon and Intel in one binary. Every private framework
# Sleight uses is reached through dlopen at runtime rather than linked, so
# there is nothing architecture-specific to port — only to build for.
#
# Each slice is built on its own and joined with lipo. Handing SwiftPM two
# --arch flags at once makes it switch to Xcode's build system (xcbuild), which
# the Command Line Tools alone don't ship, so that path only worked with a full
# Xcode install (issue #1). Pass --native to build just this machine's slice.
ARCHS=(arm64 x86_64)
if [[ "${1:-}" == "--native" ]]; then
  ARCHS=("$(uname -m)")
fi

BIN=build/bin
rm -rf "$BIN"
mkdir -p "$BIN"
for ARCH in "${ARCHS[@]}"; do
  swift build -c release --arch "$ARCH" --scratch-path ".build/$ARCH"
done
for TOOL in Sleight sleight-helper; do
  SLICES=()
  for ARCH in "${ARCHS[@]}"; do
    SLICES+=(".build/$ARCH/release/$TOOL")
  done
  lipo -create "${SLICES[@]}" -output "$BIN/$TOOL"
done

APP=build/Sleight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Sleight" "$APP/Contents/MacOS/Sleight"
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [[ -f assets/AppIcon.icns ]]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# The wake helper and everything needed to install it. It only ever leaves the
# bundle if the user turns on "Wake the Mac for automations".
cp "$BIN/sleight-helper" "$APP/Contents/Resources/sleight-helper"
cp scripts/com.kamenlevi.sleight.helper.plist "$APP/Contents/Resources/"
cp scripts/install-helper.sh scripts/uninstall-helper.sh "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/sleight-helper" "$APP/Contents/Resources/"*.sh

IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "Sleight Local Signing"; then
  IDENTITY="Sleight Local Signing"
fi
# Nested code signs first, or sealing the bundle around it fails.
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/sleight-helper"
codesign --force --sign "$IDENTITY" --identifier com.kamenlevi.sleight "$APP"
echo "Built $APP (signed: $IDENTITY, $(lipo -archs "$APP/Contents/MacOS/Sleight"))"
