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

#### 缓存结构

| 缓存 Key | 说明 |
|----------|------|
| `content_version` | 当前已知的内容版本 |
| `content_version_pending` | 待刷新的内容版本 |
| `domain_cache_{domainId}` | 领域知识点缓存 |
| `domain_version_{domainId}` | 领域缓存对应的版本 |
| `topics_cache` | 全局知识点缓存（兼容旧版） |

#### 自动更新流程

```
App 启动
    ↓
加载 manifest.json
    ↓
检查 contentVersion 变化？
    ↓
┌───┴───┐
│       │
是      否
↓       ↓
记录 pendingVersion    使用缓存
↓
切换领域时检查
↓
pendingVersion != domain_version_X ?
↓
┌───┴───┐
│       │
是      否
↓       ↓
从网络加载    使用缓存
↓
记录 domain_version_X = pendingVersion
```

#### 手动刷新

用户可以在 **个人中心 → 知识源配置 → 应用并重载** 手动刷新：

1. 清空所有领域缓存
2. 重新加载内容
3. 拉取当前领域的知识点

适用场景：
- 内容仓库更新后想立即看到最新内容
- 缓存数据异常需要重置
- 切换测试/正式环境后刷新

### 内容更新流程

1. 在内容仓库修改知识点、分类、领域等
2. 更新 `manifest.json` 的 `contentVersion`（改为今天的日期）
3. 验证内容：`npm run validate`
4. 提交并推送
5. 用户下次打开 App 会自动检测到版本变化

### 版本号格式

使用日期格式：`YYYY.MM.DD`

```json
{
  "contentVersion": "2026.05.28"
}
```

### 已删除领域的处理

内容版本更新时，App 会自动清理已删除领域的本地缓存：

```dart
// 获取当前所有领域 ID
final currentDomainIds = _domains.map((d) => d.id).toSet();

// 遍历本地缓存，清理不存在的领域
for (final key in domainCacheKeys) {
  final domainId = key.replaceFirst('domain_cache_', '');
  if (!currentDomainIds.contains(domainId)) {
    await _storage.save(key, null);  // 清除缓存
  }
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
4. 更新检查默认使用 Worker 稳定地址 `https://mianshi-zhilian-api.nontracey.workers.dev/update.json`，由 Worker 代理 GitHub latest release 中的 `update.json`。如需更换更新源，可配置 GitHub Variable `UPDATE_MANIFEST_URL`。

## 免费额度与用户量估算

### 免费的部分

| 模块 | 免费条件 |
| --- | --- |
| GitHub 公共内容仓库 | 公共仓库免费 |
| GitHub Actions | 公共仓库标准 runner 免费 |
| Flutter Web 静态站点 | Cloudflare Pages 免费额度可用 |
| 内容 JSON 静态分发 | Cloudflare Pages 免费额度可用 |
| Cloudflare Worker API | Free 计划每天 100,000 次请求 |
| Cloudflare D1 | Free 计划每天 5,000,000 行读取、100,000 行写入、总存储 5GB |
| AI 模型调用 | 用户自带 API Key，平台不承担费用 |

### 免费额度下的粗略用户量

| 场景 | 每活跃用户每天 Worker 请求 | 免费额度可支撑 DAU |
| --- | --- | --- |
| 轻度使用（只学习，偶尔同步） | 2-5 | ~20,000-50,000 |
| 正常使用（登录、同步、练习） | 5-10 | ~6,000-10,000 |
| 高频使用（大量练习、多次同步） | 10-20 | ~3,000-5,000 |
| Web 端 AI 全走 Worker 代理 | 取决于练习次数 | ~1,000-3,000 |

### 降低成本策略

1. 内容、动画、安装包全部静态化，不进数据库
2. 进度本地优先，批量同步，不每答一题写云数据库
3. D1 表必须加索引，避免全表扫描
4. 用户默认自带 API Key
5. `update.json`、`manifest.json` 使用短缓存，具体 topic 使用长缓存
