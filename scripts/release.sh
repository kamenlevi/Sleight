#!/bin/zsh
# Cuts a release: builds and signs Sleight.app, zips it, and publishes a
# GitHub release the in-app updater picks up. Usage: scripts/release.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: release.sh <version>}

# Keep the bundle version in sync — the updater compares against it.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" scripts/Info.plist

./scripts/build-app.sh

ZIP="build/Sleight-$VERSION.zip"
rm -f "$ZIP"
ditto -ck --keepParent build/Sleight.app "$ZIP"

gh release create "v$VERSION" "$ZIP" \
  --title "Sleight $VERSION" \
  --generate-notes

echo "Released v$VERSION"
