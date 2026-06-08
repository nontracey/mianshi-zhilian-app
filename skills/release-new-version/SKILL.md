---
name: release-new-version
description: 发布新版本——版本号+1、构建号递增、打新版本 tag
source: project
keywords: [发布新版本, 推送新版本, 发布新版, release new version, bump version]
---

# 发布新版本（Release New Version）

## 触发关键词

> `发布新版本` / `推送新版本` / `发布新版` / `版本号+1` / `新版本发布` / `推送新版`

## 适用场景

功能里程碑达成、重大更新或需要更新版本号时，递增版本号并将构建号递增。

## 工作流概览

```
检测变更 → 创建发布分支 → 提交功能变更(feat/fix) + 递增版本号+构建号(chore) → 创建 PR → 合并到 main → 切回 main 同步 → 打新版本 tag → 推送 tag
```

> **关键：功能变更和版本号递增必须分开提交，但放在同一个分支上。** 功能变更一个 commit，版本号递增单独一个 `chore:` commit。这样 release notes 的 git log 范围里只会有 `feat`/`fix`，不会出现 `chore: 构建号` 混入的问题。

## 前置检查

在开始发布新版本前，**必须**在项目根目录运行提交前检查脚本，确保代码通过所有质量门禁：

```bash
cd /Users/yingjunchi/code/mianshi-zhilian-app
./scripts/pre-commit-check.sh
```

该脚本依次执行：`flutter pub get` → 生成版本文件 → l10n key 校验 → `flutter analyze` → `flutter test` → `flutter build web --release`。任何一步失败则中止，修复后再继续。

## 详细步骤

### 1. 检测变更区域

```bash
cd /Users/yingjunchi/code/mianshi-zhilian-app

git status --short
git diff --cached --stat
git log origin/main..HEAD --oneline
```

变更来源分两类：

| 目录 | 版本文件 | 版本格式 |
|------|---------|---------|
| `apps/client/` | `pubspec.yaml` — `version:` 字段 | `x.x.x+buildNumber` (如 `0.1.3+112`) |
| `workers/api/` | `package.json` — `"version"` 字段 | `x.x.x` 或 `x.x.x+buildNumber` |

### 2. 递增版本号 + 构建号递增

#### apps/client (`pubspec.yaml`)

- 版本号最后一位（patch）+1
- 构建号在当前基础上 **+1**（不能重置，因为 Android 的 `versionCode` 使用构建号，必须单调递增）
- 示例：`0.1.3+112` → `0.1.4+113`

版本号递增规则：
- **patch 递增**（默认）：`0.1.3` → `0.1.4`（功能修复、小改动）
- **minor 递增** (需判断)：`0.1.3` → `0.2.0`（新增功能、破坏性变更）
- 不要频繁改 minor，保持语义化版本规范

#### workers/api (`package.json`)

- 如果 API 有变更 → 版本号 patch +1（无构建号概念）
- 示例：`0.1.0` → `0.1.1`
- 如果 API **无变更** → 保持不动

### 3. 创建发布分支 + 提交变更

在单独的分支上工作，功能变更和版本号递增分两次 commit：

```bash
# 从 main 创建发布分支
git checkout -b release/v{newVersion}

# 先提交代码变更（不碰 pubspec.yaml 版本号）
git add -A
git commit -m "feat: 新增关于页推广入口、隐私政策与 OG 图片"

# 再编辑版本号：apps/client/pubspec.yaml — patch +1，buildNumber +1
# 示例：0.1.3+112 → 0.1.4+113
# 如果 API 有变更：同步递增 workers/api/package.json

git add apps/client/pubspec.yaml
git add workers/api/package.json  # 如需要

git commit -m "chore: 版本号 0.1.3→0.1.4，构建号 112→113"
```

提交说明必须：
- **使用中文**
- **遵循 `.gitmessage` 格式**：`<type>: <中文描述>`
- 类型根据实际变更选择（`feat`/`fix`/`refactor`/`docs` 等）
- 版本号递增用 `chore:` 类型
- 标题行包含一句话总结变更

### 4. 推送分支 → 创建 PR → 合并

```bash
# 推送分支
git push origin release/v{newVersion}

# 在 GitHub 创建 PR（base: main, head: release/v{newVersion}）
# PR 通过 CI + 至少 1 人 review 后合并到 main

# 合并后切回 main 并同步
git checkout main
git pull origin main
```

### 5. 打新版本 tag

Tag 名称：`v` + 版本号（不含 `+buildNumber`）

```bash
git tag -a v{x.x.x} -m "Release v{x.x.x}"
```

示例：
```bash
git tag -a v0.1.4 -m "Release v0.1.4"
```

### 6. 推送 tag

```bash
git push origin v{newVersion}
```

> `v0.1.4` 是**新 tag**，GitHub 上不存在，所以用 `git push origin v0.1.4`（非 force-push）。
> 不需要覆盖旧 tag。

### 7. 验证

推送后，GitHub Actions Release workflow 自动触发：
- CI 验证 tag `v0.1.4` 与 `pubspec.yaml` 中 `0.1.4+113` 的版本部分一致
- 并行构建 Android / Web / Windows / macOS 四平台
- `update-manifest` job 生成 `update.json` 并发布为 latest

可在 GitHub 仓库 Actions 页面查看进度。

## 与「发布构建」的区别

| 维度 | 发布构建 | 发布新版本 |
|------|---------|-----------|
| 版本号 | 不变 | +1（patch 递增） |
| 构建号 | +1 | +1（递增，非重置） |
| Tag | 重新打当前 tag (`force-push`) | 打新 tag (如 `v0.1.4`) |
| 适用 | 日常迭代、hotfix | 功能里程碑、发布说明更新 |

## 注意事项

- **版本号一旦发布不可修改**。`v0.1.4` tag 是永久记录，不可 force-push 覆盖（不像构建 tag `v0.1.3` 可以被覆盖）。
- 发布新版本后，**下一次发布构建会自动从递增后的构建号继续**。例如 `0.1.4+113` → 下次构建 → `0.1.4+114`。
- `pubspec.yaml` 版本号不得包含字母（如 `0.1.4-beta`），否则 CI 解析会失败。
- 建议在发布新版本时同步更新 `docs/` 目录下的部署文档中的版本信息。
- 如果 `workers/api/` 也需要发布新版本，确保 API 的 `package.json` 版本号也同步递增。