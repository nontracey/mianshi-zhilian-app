#!/usr/bin/env bash
# 从 pubspec.yaml 生成 web/version.json，本地开发前运行此脚本
# 用法: bash tool/generate_version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/../web"
PUBSPEC="$SCRIPT_DIR/../pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
  echo "ERROR: pubspec.yaml not found at $PUBSPEC"
  exit 1
fi

# 解析 version: x.y.z+buildNumber
VERSION_LINE=$(grep '^version:' "$PUBSPEC" | head -1)
VERSION=$(echo "$VERSION_LINE" | sed 's/version: //' | sed 's/+.*//')
BUILD=$(echo "$VERSION_LINE" | sed 's/.*+//')

mkdir -p "$WEB_DIR"

cat > "$WEB_DIR/version.json" << EOF
{
  "version": "$VERSION",
  "buildNumber": "$BUILD",
  "releaseDate": "$(date -u +%Y-%m-%d)"
}
EOF

echo "✓ Generated $WEB_DIR/version.json: version=$VERSION build=$BUILD"
