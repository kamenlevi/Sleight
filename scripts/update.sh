#!/bin/zsh
# Manual update: pull the latest source, rebuild, swap the installed app,
# and relaunch. With the local signing identity in place (make-identity.sh),
# permissions survive this.
set -euo pipefail
cd "$(dirname "$0")/.."

git pull --ff-only
./scripts/build-app.sh

pkill -x Sleight 2>/dev/null || true
sleep 1
rm -rf /Applications/Sleight.app
cp -R build/Sleight.app /Applications/
open /Applications/Sleight.app
echo "Updated and relaunched."
