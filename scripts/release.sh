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

# Point the Homebrew tap at the release that just went out. A cask pins an
# exact checksum, so one left behind doesn't install an older Sleight — it
# fails on a checksum mismatch, which is a far more confusing way to find out
# the tap wasn't updated.
TAP_DIR="${SLEIGHT_TAP_DIR:-$HOME/homebrew-sleight}"
if [[ ! -d "$TAP_DIR/.git" ]]; then
  git clone -q https://github.com/kamenlevi/homebrew-sleight.git "$TAP_DIR" 2>/dev/null || true
fi
if [[ -d "$TAP_DIR/.git" ]]; then
  SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
  /usr/bin/sed -i '' \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    "$TAP_DIR/Casks/sleight.rb"
  if ! git -C "$TAP_DIR" diff --quiet; then
    git -C "$TAP_DIR" commit -qam "sleight $VERSION"
    git -C "$TAP_DIR" push -q
    echo "Updated the Homebrew cask to $VERSION"
  fi
else
  echo "warning: no Homebrew tap checkout — cask still points at the previous version" >&2
fi

echo "Released v$VERSION"
