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

echo "=== 1/5 推送分支: $BRANCH ==="
git push origin "$BRANCH"

echo "=== 2/5 创建 PR ==="
EXISTING_PR=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0].url // empty')
if [ -n "$EXISTING_PR" ]; then
  PR_URL="$EXISTING_PR"
  echo "PR 已存在: $PR_URL"
else
  PR_URL=$(gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY")
fi

PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "PR #$PR_NUMBER: $PR_URL"

echo "=== 3/5 等待 CI 通过 ==="
gh pr checks "$PR_NUMBER" --watch --interval 15 --required || true

echo "=== 4/5 管理员合并 PR ==="
gh pr merge "$PR_NUMBER" --merge --admin
echo "PR #$PR_NUMBER 已合并"

echo "=== 5/5 同步 main + 打 tag ==="
git checkout main
git pull origin main

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
