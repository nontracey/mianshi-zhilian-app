#!/usr/bin/env bash
set -euo pipefail

asset_dir="${1:-release-assets}"

test -f "$asset_dir/update.json"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*android*.apk' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*windows*.exe' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*macos*.dmg' -print -quit)"
test -n "$(find "$asset_dir" -maxdepth 1 -type f -name '*web*.zip' -print -quit)"
node -e '
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const [platform, item] of Object.entries(manifest.platforms || {})) {
  if (!item.assetPath || !String(item.assetPath).startsWith("/releases/latest/download/")) {
    throw new Error(`${platform} is missing a normalized assetPath`);
  }
}
' "$asset_dir/update.json"

echo "release assets ready in $asset_dir"
