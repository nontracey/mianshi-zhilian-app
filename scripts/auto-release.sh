#!/bin/bash
set -euo pipefail

MODE="${1:?Usage: auto-release.sh <build|version> <args...>}"
shift

REPO_ROOT="/Users/yingjunchi/code/mianshi-zhilian-app"
cd "$REPO_ROOT"

if [ "$MODE" = "build" ]; then
  BUILD_NUMBER="${1:?Usage: auto-release.sh build <buildNumber> <version>}"
  VERSION="${2:?Usage: auto-release.sh build <buildNumber> <version>}"
  BRANCH="release/build-${BUILD_NUMBER}"
  TAG="v${VERSION}"
  PR_TITLE="build: 发布构建 $BUILD_NUMBER (v$VERSION)"
  PR_BODY="自动发布构建 #$BUILD_NUMBER"
  FORCE_TAG=true
elif [ "$MODE" = "version" ]; then
  NEW_VERSION="${1:?Usage: auto-release.sh version <newVersion> <buildNumber>}"
  BUILD_NUMBER="${2:?Usage: auto-release.sh version <newVersion> <buildNumber>}"
  BRANCH="release/v${NEW_VERSION}"
  TAG="v${NEW_VERSION}"
  PR_TITLE="chore: 发布版本 v$NEW_VERSION (build $BUILD_NUMBER)"
  PR_BODY="自动发布版本 v$NEW_VERSION"
  FORCE_TAG=false
else
  echo "Unknown mode: $MODE (use 'build' or 'version')"
  exit 1
fi

echo "=== 1/6 推送分支: $BRANCH ==="
git push origin "$BRANCH"

echo "=== 2/6 创建 PR ==="
PR_URL=$(gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY")

PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "PR #$PR_NUMBER: $PR_URL"

echo "=== 3/7 启用 auto-merge ==="
gh pr merge "$PR_NUMBER" --auto --merge

echo "=== 4/7 等待 CI 通过并自动合并 ==="
while true; do
  STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state')
  MERGED=$(gh pr view "$PR_NUMBER" --json merged --jq '.merged')
  if [ "$STATE" = "MERGED" ] || [ "$MERGED" = "true" ]; then
    echo "PR #$PR_NUMBER 已自动合并"
    break
  fi
  sleep 15
done

echo "=== 5/6 同步 main ==="
git checkout main
git pull origin main

echo "=== 6/6 打 tag: $TAG ==="
if [ "$FORCE_TAG" = true ]; then
  git tag -f "$TAG"
  git push origin "$TAG" --force
  echo "Tag $TAG 已强制更新并推送"
else
  git tag -a "$TAG" -m "Release $TAG"
  git push origin "$TAG"
  echo "新 Tag $TAG 已创建并推送"
fi

echo "=== 完成 ==="
