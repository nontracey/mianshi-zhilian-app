# 部署说明

面试智练使用 GitHub Actions 构建 Flutter Web、Android APK、Windows installer exe/zip、macOS dmg/zip，并把 tag 构建产物上传到 GitHub Releases。Cloudflare 部署由 GitHub push 触发。

## CI/CD 工作流

| 工作流 | 触发条件 | 功能 |
|--------|---------|------|
| `CI` | PR 和 `main` push | `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build web --release` |
| `Deploy web` | `main` push 且 `apps/client/**` 变更 | 构建 Flutter Web 后通过 `wrangler pages deploy` 部署到 Cloudflare Pages |
| `Deploy worker` | `main` push 且 `workers/api/**` 变更 | 检查 D1 schema 覆盖，执行 `init-db.sql`，再通过 `wrangler pages deploy` 部署 Cloudflare Pages Functions (API) |
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
│  │ Pages (App)  │  │ Pages        │  │ Pages Func-  │      │
│  │ de5.net 主用 │  │ (Content)    │  │ tions (API)  │      │
│  │ pages.dev    │  │ de5.net 主用 │  │ de5.net 主用 │      │
│  │ 备用         │  │ pages.dev 备 │  │ pages.dev 备 │      │
│  └──────────────┘  └──────────────┘  └──────┬───────┘      │
│                                             │               │
│                                      ┌──────▼───────┐      │
│                                      │ D1 Database  │      │
│                                      │ (User Data)  │      │
│                                      └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## 访问地址

| 服务 | 主用 | 备用 |
|------|------|------|
| Web App | https://mianshizhilian-app.nontracey.de5.net | https://mianshi-zhilian-app.pages.dev |
| 内容 CDN | https://mianshizhilian-content.nontracey.de5.net | https://mianshi-zhilian-content.pages.dev |
| Worker API | https://mianshizhilian-api.nontracey.de5.net | https://mianshi-zhilian-api.pages.dev |

## 必需配置

### GitHub Secrets（加密存储）

| Secret | 说明 |
|--------|------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token，需要 Pages 和 Workers 权限 |
| `D1_DATABASE_ID` | app Worker 绑定的 D1 数据库 ID，需要与 studio-api 共享同一个 D1；二者部署面和 API 实现分开，不互相覆盖 |
| `D1_STAGING_DATABASE_ID` | PR 预览环境使用的 D1 数据库 ID |
| `JWT_SECRET` | 用户认证 JWT 签名密钥，需要在 Cloudflare Pages Dashboard 中手动配置为加密环境变量 |
| `KV_NAMESPACE_ID` | 生产 Worker KV 命名空间 ID |
| `KV_STAGING_NAMESPACE_ID` | PR 预览环境 Worker KV 命名空间 ID |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | 可选，Android 正式签名 keystore 的 base64 内容 |
| `ANDROID_RELEASE_STORE_PASSWORD` | 可选，Android keystore 密码 |
| `ANDROID_RELEASE_KEY_ALIAS` | 可选，Android 签名 key alias |
| `ANDROID_RELEASE_KEY_PASSWORD` | 可选，Android 签名 key 密码 |

### GitHub Variables（非加密）

| Variable | 说明 |
|----------|------|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账号 ID |

### Cloudflare Pages Dashboard 配置

| 配置项 | 说明 |
|--------|------|
| `JWT_SECRET` | 用户认证 JWT 签名密钥，在 Pages Dashboard 中设为加密环境变量 |
| D1 database binding | 绑定 `mianshi-zhilian-db` 数据库 |
| KV namespace binding | 绑定内容缓存 KV 命名空间 |

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
```

## App Worker 后台能力

App Worker 仍坚持本地优先：学习记录、AI 配置和用户自定义同步目标优先留在本地，平台侧不强制接管练习明细。Worker 只维护平台账号、工单、访问聚合统计和安全限制。

新增 D1 表以 `workers/api/init-db.sql` 作为幂等 schema 基线。`Deploy worker` 会在部署 Pages Functions 前执行 `npm run check:migrations`，确认 Worker 代码中的表、索引和补列都已覆盖到 `init-db.sql`；随后执行 `wrangler d1 execute <db> --remote --file=./init-db.sql`。本地提交前的 `./scripts/pre-commit-check.sh` 也会跑同一个迁移覆盖检查，避免功能上线后缺表。

| 表 | 说明 |
| --- | --- |
| `users` | 平台账号、昵称、角色、禁用状态和最后登录时间 |
| `refresh_tokens` | 刷新令牌、轮换关系和撤销状态 |
| `tickets` | 登录用户反馈/问题工单，以及未登录密码重置工单；密码重置提交响应只回执 id/type/status/created_at，不回显联系方式和说明正文 |
| `user_devices` | 登录后的安装级设备 ID 与账号绑定关系，支持一用户多设备和安全限制 |
| `daily_visit_stats` | 按天、设备聚合访问次数和访问时长；`user_id` 兼容保留但新写入和初始化隐私清理会置空 |
| `daily_section_stats` | 按天、设备聚合页面入口访问；`user_id` 兼容保留但不再写入 |
| `daily_feature_stats` | 按天、设备聚合 AI 评估、手动同步、工单提交、登录；`user_id` 兼容保留但不再写入 |
| `security_block_rules` | 后台维护的设备/IP/平台/版本/型号限制规则，未登录请求也会生效 |

访问统计默认开启，但客户端会先写本地 buffer，约每 30 分钟批量上报。上报失败不会影响学习、登录以外的本地功能。统计上报不包含完整练习回答或 API Key；Worker 只保留设备维度聚合，`analytics_batches` 去重记录 30 天后清理。

## 内容更新注意事项

### ⚠️ 更新内容后必须更新版本号

App 通过 `manifest.json` 中的 `contentVersion` 字段检测内容是否有更新。如果内容仓库更新了内容但没有更新版本号，App 会继续使用本地缓存的旧内容。

### 内容环境隔离

正式、测试、草稿三个入口路径保持不变：

- 正式：`manifest.json`
- 测试：`staging-manifest.json`，经 App API 代理时仍请求 `/content/test/manifest.json`
- 草稿：`draft-manifest.json`，经 App API 代理时仍请求 `/content/draft/manifest.json`

不同入口会指向不同的 domain/topic 文件。正式内容使用 `domains/`、`topics/`；测试内容使用 `staging/domains/`、`staging/topics/`；草稿内容使用 `draft/domains/`、`draft/topics/`。

客户端加载规则：

1. 先读取当前环境 manifest。
2. 按 `manifest.domains[].entry` 请求 domain 文件。
3. 按 `domain.categories[].topics[]` 请求 topic 文件。
4. 缓存 key 使用 topic 相对路径归一化结果，避免不同环境同名 topic 串缓存。

App 不应硬编码 `/domains/{id}.json` 或 `/topics/{domain}/{file}.json`。这样内容工作台编辑草稿和测试内容时，不会覆盖正式用户正在使用的同一知识点。

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
3. 验证内容：`npm run validate`、`npm run quality:scan`、`npm run quality:audit`
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
- 图解降级链按 `sources[]` 顺序渲染：`svg.path` 加载 `assets/` 资源，`svg.content` 渲染内联 `<svg...>`，`mermaid.content` 渲染轻量 Mermaid 子集，`text.content` 兜底。`compareTable` 是独立卡片，不作为 `diagram.sources`。

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

1. 在 GitHub 仓库配置 `CLOUDFLARE_API_TOKEN` secret 后，Web 和 Pages Functions 部署会在 push 到 `main` 时自动触发。
2. 在 Cloudflare Pages Dashboard 中配置 D1 数据库绑定、KV 命名空间绑定和环境变量。
3. Android release 构建已支持 keystore secrets；未配置时使用 debug 签名兜底以保证本地和预览构建可用。正式分发前仍需补 Windows 代码签名、macOS Developer ID 签名和 notarization。
4. 更新检查使用 `RouteResolver.appApi + /update.json`，由客户端自动在主用 `https://mianshizhilian-api.nontracey.de5.net` 与备用 `https://mianshi-zhilian-api.pages.dev` 间选择。生产构建不再使用 `API_BASE_URL` / `UPDATE_MANIFEST_URL`。下载安装包、本机语音模型和 ONNX Runtime 时默认会探测 GitHub 官方、用户自定义镜像和 ghfast.top，优先使用响应最快的可达线路；用户可在 App 的"关于与更新 → ⚙️ 下载设置"中配置自定义镜像站前缀，并在"线路诊断"中切换下载源模式。

## 免费额度与用户量估算

### 免费的部分

| 模块 | 免费条件 |
| --- | --- |
| GitHub 公共内容仓库 | 公共仓库免费 |
| GitHub Actions | 公共仓库标准 runner 免费 |
| Flutter Web 静态站点 | Cloudflare Pages 免费额度可用 |
| 内容 JSON 静态分发 | Cloudflare Pages 免费额度可用 |
| Cloudflare Pages Functions API | Free 计划每天 100,000 次请求 |
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
