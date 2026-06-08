---
name: release-build
description: 发布新构建——检测变更区域→递增对应构建号→提交→打 tag→推送，版本号不变
source: project
keywords: [发布构建, 推送构建, 推送构建号, 重新打 tag, release build, bump build]
---

# 发布构建（Release Build）

## 触发关键词

> `发布构建` / `推送构建` / `推送构建号` / `重新打 tag` / `发布新构建` / `增加构建号` / `构建号+1`

## 适用场景

完成一个或多个功能/修复后，需要发布新构建（构建号 +1，版本号保持不变）。

## 工作流概览

```
检测变更 → 创建发布分支 → 提交功能变更(feat/fix) + 递增构建号(chore) → 创建 PR → 合并到 main → 切回 main 同步 → 重新打当前版本 tag → 强制推送 tag
```

> **关键：功能变更和版本号递增必须分开提交，但放在同一个分支上。** 功能变更一个 commit，构建号递增单独一个 `chore:` commit。这样 release notes 的 git log 范围里只会有 `feat`/`fix`，不会出现 `chore: 构建号` 混入的问题。

## 前置检查

在开始发布构建前，**必须**在项目根目录运行提交前检查脚本，确保代码通过所有质量门禁：

```bash
cd /Users/yingjunchi/code/mianshi-zhilian-app
./scripts/pre-commit-check.sh
```

该脚本依次执行：`flutter pub get` → 生成版本文件 → l10n key 校验 → `flutter analyze` → `flutter test` → `flutter build web --release`。任何一步失败则中止，修复后再继续。

## 详细步骤

### 1. 检测变更区域

```bash
cd /Users/yingjunchi/code/mianshi-zhilian-app

# 未暂存变更（working tree）
git status --short

# 已暂存未提交变更
git diff --cached --stat

# 已提交但未推送的 commit
git log origin/main..HEAD --oneline
```

变更来源分两类：

| 目录 | 版本文件 | 版本格式 |
|------|---------|---------|
| `apps/client/` | `pubspec.yaml` — `version:` 字段 | `x.x.x+buildNumber` (如 `0.1.3+112`) |
| `workers/api/` | `package.json` — `"version"` 字段 | `x.x.x` 或 `x.x.x+buildNumber` |

### 2. 递增构建号

规则：
- `apps/client/` 有变更 → `pubspec.yaml` 中 `version` 字段的 `+buildNumber` 部分 +1。
- `workers/api/` 有变更 **且** `package.json` 的 `version` 已包含 `+buildNumber` → 同样 +1；若无 `+buildNumber` 则不动（兼容旧格式）。

示例：
- `0.1.3+112` → `0.1.3+113`
- 多个区域有变更 → 各自 +1，commit message 中并列说明。

### 3. 创建发布分支 + 提交变更

在单独的分支上工作，功能变更和构建号递增分两次 commit：

```bash
# 从 main 创建发布分支
git checkout -b release/build-{newBuildNumber}

# 先提交代码变更（不碰 pubspec.yaml 版本号）
git add -A
git commit -m "feat: 修复登录页键盘弹起按钮遮挡

更新 auth_provider.dart 状态同步逻辑"

# 再编辑构建号：apps/client/pubspec.yaml 中 version 字段（buildNumber +1）
# 如果 API 也有变更且使用 buildNumber：同步递增 workers/api/package.json

git add apps/client/pubspec.yaml
# 如果 API 也有变更：
git add workers/api/package.json

git commit -m "chore: 构建号 112→113"
```

提交说明必须：
- **使用中文**
- **遵循 `.gitmessage` 格式**：`<type>: <中文描述>`
- 类型根据实际变更选择（`feat`/`fix`/`refactor`/`docs` 等）
- 构建号递增用 `chore:` 类型

### 4. 推送分支 → 创建 PR → 合并

```bash
# 推送分支
git push origin release/build-{newBuildNumber}

# 在 GitHub 创建 PR（base: main, head: release/build-{newBuildNumber}）
# PR 通过 CI + 至少 1 人 review 后合并到 main

# 合并后切回 main 并同步
git checkout main
git pull origin main
```

### 5. 重新打 tag + 推送

```bash
# 重新打当前版本 tag（覆盖旧 tag）
git tag -f v{version}
git push origin v{version} --force
```

> 注意：`v{version}` 取自 `pubspec.yaml` 的版本号（不含 `+buildNumber`），如 `v0.1.3`。无论是否强制推送，该 tag 始终指向当前发布的 commit。

### 6. 验证

推送后，GitHub Actions Release workflow 自动触发：
- CI 在 `prepare-release` job 中验证 tag 与 pubspec 版本一致
- 并行构建 Android / Web / Windows / macOS 四平台
- `update-manifest` job 生成 `update.json` 并发布为 latest

可在 GitHub 仓库 Actions 页面查看进度。

## 与「发布新版本」的区别

| 维度 | 发布构建 | 发布新版本 |
|------|---------|-----------|
| 版本号 | 不变 | +1（patch 递增） |
| 构建号 | +1 | +1（递增，非重置） |
| Tag | 重新打当前 tag (`force-push`) | 打新 tag (如 `v0.1.4`) |
| 适用 | 日常迭代、hotfix | 功能里程碑、发布说明更新 |

## 注意事项

- 构建号仅用于 App 内部版本比较（新旧判断），不对外展示，所以可以反复递增。
- `pubspec.yaml` 版本号不得包含字母（如 `0.1.3-beta`），否则 CI 解析会失败。
- 如果变更仅涉及 `workers/api/` 而 `apps/client/` 无变化，且 API 无构建号，则只需提交代码无需递增任何构建号，也不需要重新打 tag。