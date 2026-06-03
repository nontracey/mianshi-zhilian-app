# 面试智练 App — 项目指南

## 项目概述

面试智练（mianshi-zhilian-app）是一款 AI 驱动的主动回忆学习工作台，通过"知识学习 → 主动复述 → AI 评估纠错 → 掌握度更新"帮助用户系统备战技术面试。项目由三个独立的 Git 仓库组成：

| 仓库 | 说明 |
|------|------|
| `mianshi-zhilian-app`（本仓库） | Flutter 多平台客户端 + Cloudflare Worker API |
| `mianshi-zhilian-content` | 知识内容仓库（manifest/domain/topic 三层结构） |
| `mianshi-zhilian-content-studio` | 内容管理工作台（React + Hono） |

核心原则：**知识只有一份（content 仓库）**，App 只消费不定义知识结构，studio 只面向管理员。

### 技术栈

| 模块 | 技术 |
|------|------|
| 客户端 | Flutter (Web / Android / macOS / Windows) |
| 后端 API | Cloudflare Pages Functions (TypeScript) |
| 数据库 | Cloudflare D1 + 本地 SQLite |
| 内容 CDN | Cloudflare Pages 静态 JSON |
| 状态管理 | Provider |
| CI/CD | GitHub Actions |
| 版本号 | SemVer + buildNumber（如 `0.1.3+107`） |

### 访问地址

| 服务 | 主用 | 备用 |
|------|------|------|
| Web App | https://mianshi-zhilian-app.pages.dev | https://mianshizhilian-app.nontracey.de5.net |
| 内容 CDN | https://mianshi-zhilian-content.pages.dev | https://mianshizhilian-content.nontracey.de5.net |
| Worker API | https://mianshi-zhilian-api.pages.dev | https://mianshizhilian-api.nontracey.de5.net |

官方 App API、Content CDN、更新清单和官方下载镜像统一走 `RouteResolver` + `EndpointFallbackClient`。生产构建不再注入 `API_BASE_URL` / `UPDATE_MANIFEST_URL`；本地线路偏好和最近可用线路只存当前设备，不进入账号同步。

---

## 项目结构

```
mianshi-zhilian-app/
├── apps/client/                   # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart              # 应用入口，Provider 注入
│   │   ├── models/                # 数据模型（AppSettings, User, Topic 等）
│   │   ├── pages/
│   │   │   ├── auth/              # 登录注册页面
│   │   │   ├── learning/          # 学习（首页、目录、详情）
│   │   │   ├── practice/          # 练习（复述、模拟面试、今日复习）
│   │   │   ├── prep/              # 面试准备
│   │   │   ├── mastery/           # 掌握度看板
│   │   │   └── profile/           # 个人中心
│   │   ├── providers/             # Provider 状态管理（7 个 Provider）
│   │   ├── services/              # 服务层（API、AI、同步、更新、分析）
│   │   ├── widgets/               # 通用组件
│   │   ├── theme/                 # 主题系统（4 种内置主题 + 自定义）
│   │   ├── utils/                 # 工具类
│   │   ├── l10n/                  # 自定义国际化（l10n.dart）
│   │   └── generated/             # 自动生成的版本文件
│   ├── pubspec.yaml               # 版本号在此定义
│   └── web/                       # Web 平台配置
├── workers/api/                   # Cloudflare Worker API
│   ├── src/index.ts               # 全部路由和处理逻辑
│   ├── wrangler.toml              # Worker 配置（D1 绑定、环境变量）
│   ├── package.json
│   ├── init-db.sql                # D1 数据库初始化 SQL
│   └── tools/                     # Worker 工具/辅助模块
├── docs/                          # 设计文档
│   ├── design.md                  # 完整开发设计方案（1413 行）
│   ├── deploy.md                  # 部署说明
│   ├── update.md                  # 软件更新机制
│   └── sponsor.md                 # 赞助页面
├── scripts/                       # 构建脚本
│   ├── pre-commit-check.sh        # 提交前 6 步检查
│   ├── build_update_manifest.dart # 生成 update.json
│   └── verify_release_assets.sh   # 验证发布资产完整性
├── skills/                        # 项目级 AI 技能（skills）
│   ├── doc-code-audit/            # 文档 vs 代码一致性审计
│   └── flutter-ui-l10n-contract/  # Flutter UI L10n 契约检查
└── .github/workflows/             # CI/CD（4 个 workflow）
    ├── ci.yml                     # PR/main push：analyze + test + build web
    ├── deploy-web.yml             # main push：Flutter Web → Cloudflare Pages
    ├── deploy-worker.yml          # main push：Worker → Cloudflare Pages Functions
    └── release.yml                # tag push：多平台并行构建 → GitHub Releases
```

---

## 构建与运行

### 前置条件

- Flutter SDK 3.41+
- Node.js 22+
- Dart SDK 3.11.5+

### 本地开发

```bash
# 启动 Flutter 客户端
cd apps/client
flutter pub get
bash tool/generate_version.sh      # 生成版本文件
flutter run -d chrome              # Web
flutter run -d macos               # macOS

# 启动 Worker（可选）
cd workers/api
npm install
npx wrangler dev
```

### 提交前检查

```bash
# 项目根目录运行，必做！
./scripts/pre-commit-check.sh
```

依次执行：
1. `flutter pub get`
2. `bash tool/generate_version.sh`
3. `python3 lib/l10n/check_l10n_keys.py`（l10n 规则检查）
4. `flutter analyze --no-fatal-infos`
5. `flutter test`
6. `flutter build web --release`

---

## 开发约定

### 版本号管理

- `pubspec.yaml` 中的 `version` 字段格式：`x.x.x+buildNumber`（如 `0.1.3+107`）
- `buildNumber` 用于软件更新新旧判断，**每次发版必须递增**
- 发布 tag（`vx.x.x`）必须与 pubspec.yaml 中的版本号一致
- `tool/generate_version.sh` 生成版本文件供运行时使用

### 提交规范

使用 **Conventional Commits** 格式，**消息正文（description）统一用中文**，确保 release notes 和 App 内更新弹窗展示一致的中文内容。

```
<type>: <中文描述>
```

| Type | 说明 | Release notes 分组 |
|------|------|-------------------|
| `feat` | 新功能 | ✨ 新功能 |
| `fix` | 问题修复 | 🐛 问题修复 |
| `docs` | 文档更新 | 📝 文档更新 |
| `refactor` | 重构（非功能变更） | 🔧 其他改动 |
| `perf` | 性能优化 | 🔧 其他改动 |
| `test` | 测试相关 | 🔧 其他改动 |
| `chore` | 构建/工具/配置 | 🔧 其他改动 |
| `ci` | CI/CD 变更 | **排除**（不出现于 release notes） |
| `revert` | 回退操作 | **排除** |
| `merge` | 合并分支 | **排除** |

原则：
- **描述聚焦"为什么做"和"做了什么"**，而非实现细节 — release notes 直接复用 commit 描述
- 一行写完，不用 body 段落。需要额外上下文写代码注释或 PR description
- `ci:` / `revert:` / `merge` 不会出现在 release notes 中，适合 CI 调参、回退等不关心用户的变更

示例：

```
feat: 掌握度看板支持按月筛选
fix: 登录页键盘弹起后按钮被遮挡
refactor: AuthProvider 改用 ChangeNotifierProxyProvider 同步语言设置
chore: buildNumber 103→104
ci: 添加 pub-cache 缓存加速依赖安装
```

### 国际化（L10n）

使用**自定义静态类**方案（非 flutter_intl / easy_localization）：

- 文件：`lib/l10n/l10n.dart`（`_zh` / `_en` 两套 map）
- Key 为英文 `snake_case`，不能包含中文、Unicode 或参数占位符
- `get(key, lang)`：按语言查找，fallback 链：中文 → 英文 → key 本身
- `getp(key, lang, params)`：模板插值，支持 `{param}` 替换
- UI 中禁止硬编码中文展示文本；所有 chrome 文案必须通过 `l10n.get()`
- 维护脚本：`python3 lib/l10n/check_l10n_keys.py`（提交前自动运行）
- 提供 `LocalizationProvider`（ChangeNotifier）响应式切换

### 状态管理

- 使用 `Provider`（6.x），通过 `MultiProvider` 注入到组件树
- 主要 Provider：
  - `AuthProvider` — 用户认证
  - `ContentProvider` — 知识内容加载和缓存
  - `AiProvider` — AI 配置和请求
  - `ProgressProvider` — 学习进度与掌握度
  - `SettingsProvider` — 应用设置
  - `LocalizationProvider` — 语言切换

### 数据架构

- **本地优先**：学习记录、AI 配置、设置默认存储在本地 SQLite / SharedPreferences
- **云端同步**：通过 Worker API 批量同步，非实时写入
- **知识内容**：完全通过 manifest.json 驱动，不嵌入 App 代码
- **Worker API** 职责：用户认证、工单、访问统计、安全限制、代理 update.json

### 内容缓存机制

| 缓存 Key | 说明 |
|----------|------|
| `content_version` | 当前已知的内容版本 |
| `content_version_pending` | 待刷新的内容版本 |
| `domain_cache_{domainId}` | 领域知识点缓存 |
| `domain_version_{domainId}` | 领域缓存对应的版本 |

App 启动 → 加载 manifest 检查 contentVersion → 有变化则记录 pendingVersion → 切换领域时按需加载新内容。

### CI/CD

| 工作流 | 触发条件 | 行为 |
|--------|---------|------|
| `CI` | PR / main push | flutter analyze + test + build web |
| `Deploy web` | main push（apps/client 变更） | Cloudflare Pages 部署 |
| `Deploy worker` | main push（workers/api 变更） | Cloudflare Pages Functions 部署 |
| `Release` | 推送 `v*` tag | 并行构建 Android/Windows/macOS/Web → GitHub Releases |

所需 GitHub Secrets：`CLOUDFLARE_API_TOKEN`、`D1_DATABASE_ID`、`JWT_SECRET`
所需 GitHub Variables：`CLOUDFLARE_ACCOUNT_ID`

Android release 支持可选正式签名 secrets：`ANDROID_RELEASE_KEYSTORE_BASE64`、`ANDROID_RELEASE_STORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD`。未配置时会使用 debug signing 作为本地/预览兜底，不阻塞构建。

### 发布流程

```bash
# 1. 更新 apps/client/pubspec.yaml 版本号
# 2. 提交
git add -A && git commit -m "chore: bump version to x.x.x"
git push origin main
# 3. 打 tag
git tag -a vx.x.x -m "Release vx.x.x"
git push origin vx.x.x
# 4. Release workflow 自动构建并上传到 GitHub Releases
```

### 主题系统

4 种内置主题：典雅白、气质黑、午夜蓝、活力橙
支持用户自定义主色/强调色、字体大小、卡片密度
主题配置存储在本地，登录后可同步到云端

### AI 配置

- 支持多 AI 配置（Base URL / API Key / 模型名）
- macOS/Android/Windows 端直连用户自定义 URL
- Web 端因 CORS 限制可走 Worker 代理
- API Key 默认仅保存在本地，不上传云端
- 支持流式输出（打字机模式）

### 设计理念

- **不花哨，像一个认真备战面试的控制台**
- 内容密度高、结构清楚、状态反馈明确
- 卡片用于知识点、掌握状态、AI 反馈
- 大面积页面区块保持干净、可扫描
- 支持游客模式 → 登录后迁移本地进度
- 用户自带 API Key，平台不承担 AI 调用成本
