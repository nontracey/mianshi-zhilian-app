# 部署说明

面试智练使用 GitHub Actions 构建 Flutter Web、Android APK、Windows installer exe/zip、macOS dmg/zip，并把 tag 构建产物上传到 GitHub Releases。Cloudflare 部署由 GitHub push 触发。

## CI/CD 工作流

| 工作流 | 触发条件 | 功能 |
|--------|---------|------|
| `CI` | PR 和 `main` push | `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build web --release` |
| `Deploy web` | `main` push 且 `apps/client/**` 变更 | 构建 Flutter Web 后通过 `wrangler pages deploy` 部署到 Cloudflare Pages |
| `Deploy worker` | `main` push 且 `workers/api/**` 变更 | 通过 `wrangler deploy` 发布 Worker API |
| `Deploy content` | 内容仓库 `main` push | 验证内容格式后部署到 Cloudflare Pages |
| `Release` | 推送 `v*` tag | 并行构建各平台安装包并上传到 GitHub Releases |

## 部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                        GitHub                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ mianshi-     │  │ mianshi-     │  │ mianshi-     │      │
│  │ zhilian-app  │  │ zhilian-     │  │ zhilian-     │      │
│  │              │  │ content      │  │ content-     │      │
│  │              │  │              │  │ studio       │      │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘      │
│         │                 │                                  │
│         ▼                 ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 GitHub Actions                        │   │
│  │  CI │ Deploy web │ Deploy worker │ Deploy content    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
         │                 │
         ▼                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Pages (App)  │  │ Pages        │  │ Workers      │      │
│  │              │  │ (Content)    │  │ (API)        │      │
│  │ app.pages.   │  │ content.     │  │ api.workers. │      │
│  │ dev          │  │ pages.dev    │  │ dev          │      │
│  └──────────────┘  └──────────────┘  └──────┬───────┘      │
│                                             │               │
│                                      ┌──────▼───────┐      │
│                                      │ D1 Database  │      │
│                                      │ (User Data)  │      │
│                                      └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## 访问地址

| 服务 | 地址 |
|------|------|
| Web App | https://mianshi-zhilian-app.pages.dev |
| 内容 CDN | https://mianshi-zhilian-content.pages.dev |
| Worker API | https://mianshi-zhilian-api.nontracey.workers.dev |

## 必需配置

### GitHub Secrets（加密存储）

| Secret | 说明 |
|--------|------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token，需要 Pages 和 Workers 权限 |

### GitHub Variables（非加密）

| Variable | 说明 |
|----------|------|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账号 ID |

### Cloudflare Secrets

| Secret | 说明 |
|--------|------|
| `JWT_SECRET` | 用户认证 JWT 签名密钥 |

### 创建 Cloudflare API Token

1. 登录 https://dash.cloudflare.com/profile/api-tokens
2. 点击 "Create Token"
3. 使用 "Custom token" 模板
4. 权限设置：
   - Account - Cloudflare Pages - Edit
   - Account - Workers Scripts - Edit
   - Account - D1 - Edit
5. 创建后复制 token，配置到 GitHub Secrets

### 创建 D1 数据库

```bash
# 登录 Cloudflare
npx wrangler login

# 创建数据库（亚太区域）
npx wrangler d1 create mianshi-zhilian-db --location apac

# 设置 JWT Secret
echo "your-secret-key" | npx wrangler secret put JWT_SECRET
```

## 内容更新注意事项

### ⚠️ 更新内容后必须更新版本号

App 通过 `manifest.json` 中的 `contentVersion` 字段检测内容是否有更新。如果内容仓库更新了内容但没有更新版本号，App 会继续使用本地缓存的旧内容。

### App 缓存机制

```dart
// App 启动时检查内容版本
final remoteVersion = _manifest?['contentVersion'];
final localVersion = await _storage.load('content_version');

if (remoteVersion != localVersion) {
  // 版本不同，清除缓存并重新加载
  _topics = {};
  await _storage.save('topics_cache', {});
  await _storage.save('content_version', remoteVersion);
}
```

### 内容更新流程

1. 在内容仓库修改知识点、分类、领域等
2. 更新 `manifest.json` 的 `contentVersion`（改为今天的日期）
3. 验证内容：`npm run validate`
4. 提交并推送

### 版本号格式

使用日期格式：`YYYY.MM.DD`

```json
{
  "contentVersion": "2026.05.28"
}
```

## 内容缓存约定

- 知识目录中的 `知识查阅` 会打开知识详情的学习 Tab，`学习模式` 会直接进入复述练习 Tab。
- App 按领域独立缓存 topic，切换领域时按需加载。
- 内容仓库生成的 learningCards 包含解释、机制拆解、对比/图示/代码、面试回答模板和 checklist，App 按 schema 通用渲染。

## 发布流程

### 1. 更新版本号

编辑 `apps/client/pubspec.yaml`：

```yaml
version: x.x.x+xxx  # 例如 0.2.0+200
```

### 2. 提交并推送

```bash
git add -A
git commit -m "chore: bump version to x.x.x"
git push origin main
```

### 3. 创建 Tag

```bash
git tag -a vx.x.x -m "Release vx.x.x - 更新说明"
git push origin vx.x.x
```

### 4. 自动构建

推送 tag 后，`Release` 工作流会自动：
- 构建 Android APK
- 构建 Windows installer 和 zip
- 构建 macOS dmg 和 zip
- 构建 Web zip
- 生成 `update.json`
- 上传所有资产到 GitHub Releases

## 还需要人工配置

1. 在 GitHub 仓库配置 `CLOUDFLARE_API_TOKEN` secret 后，Web 和 Worker 部署会在 push 到 `main` 时自动触发。
2. 在 Cloudflare Workers 配置 D1 数据库绑定和 JWT Secret。
3. 正式分发前补 Android keystore、Windows 代码签名、macOS Developer ID 签名和 notarization。
4. 如需稳定更新地址，把 release 生成的 `update.json` 同步到 Cloudflare Pages/R2 的 `latest.json`。
