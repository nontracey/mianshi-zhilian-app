#!/usr/bin/env bash
# 从 pubspec.yaml 生成 lib/generated/app_version.g.dart 和 web/version.json
# 用法: bash tool/generate_version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/../web"
GENERATED_DIR="$SCRIPT_DIR/../lib/generated"
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
mkdir -p "$GENERATED_DIR"

cat > "$GENERATED_DIR/app_version.g.dart" << EOF
// Generated from pubspec.yaml. Run \`bash tool/generate_version.sh\` after
// changing the app version.
const generatedAppVersion = '$VERSION';
const generatedBuildNumber = $BUILD;
const generatedFullVersion = '$VERSION+$BUILD';
EOF

cat > "$WEB_DIR/version.json" << EOF
{
  "version": "$VERSION",
  "build_number": "$BUILD",
  "releaseDate": "$(date -u +%Y-%m-%d)"
}
EOF

echo "✓ Generated app version files: version=$VERSION build=$BUILD"
