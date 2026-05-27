#!/usr/bin/env bash
set -euo pipefail

asset_dir="${1:-release-assets}"

test -f "$asset_dir/update.json"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*android*.apk' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*windows*.exe' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*macos*.dmg' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*web*.zip' -print -quit)"

echo "release assets ready in $asset_dir"
