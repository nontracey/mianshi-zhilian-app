# 面试智练 App — QWEN.md

> 本文件是 Qwen Code 在本仓库工作时的指令性上下文。约定优先级：本文件 > README.md > CLAUDE.md。

## 项目概述

**面试智练 (mianshi-zhilian-app)** 是一款本地优先（local-first）的 AI 主动回忆学习工作台，帮助用户通过"知识学习 → 主动复述 → AI 评估纠错 → 掌握度更新"系统备战技术面试。

本仓库是三仓库架构中的 **客户端 + API** 仓：

| 仓库 | 职责 |
|------|------|
| `mianshi-zhilian-app`（本仓库） | Flutter 多平台客户端 + Cloudflare Pages Functions API |
| `mianshi-zhilian-content` | 知识内容仓库（manifest/domain/topic 三层结构，CDN 静态 JSON） |
| `mianshi-zhilian-content-studio` | 内容管理工作台（React + Hono，仅管理员） |

核心原则：**知识只有一份（content 仓库）**，App 只消费不定义知识结构。

### 技术栈

| 模块 | 技术 |
|------|------|
| 客户端 | Flutter 3.11+（Web / Android / macOS / Windows，无 iOS） |
| 状态管理 | Provider 6.x |
| 路由 | go_router 17.x（shell route + bottom nav） |
| 后端 API | Cloudflare Pages Functions（不是独立 Worker），TypeScript |
| 数据库 | Cloudflare D1（SQLite）+ KV |
| 内容 CDN | Cloudflare Pages 静态 JSON |
| 本地存储 | shared_preferences（业务）+ flutter_secure_storage（敏感凭证） |
| 语音 | speech_to_text（系统）+ sherpa_onnx（离线）+ AI 转写 |
| 测试 | flutter_test（客户端）+ vitest（Worker） |
| CI/CD | GitHub Actions（6 个 workflow） |

### 访问地址

| 服务 | 主用 | 备用 |
|------|------|------|
| Web App | https://mianshi-zhilian-app.pages.dev | https://mianshizhilian-app.nontracey.de5.net |
| 内容 CDN | https://mianshi-zhilian-content.pages.dev | https://mianshizhilian-content.nontracey.de5.net |
| Worker API | https://mianshi-zhilian-api.pages.dev | https://mianshizhilian-api.nontracey.de5.net |

主备路线统一走 `RouteResolver` + `EndpointFallbackClient`。**生产构建不再注入 `API_BASE_URL` / `UPDATE_MANIFEST_URL`**；本地线路偏好和最近可用线路只存当前设备，不进入账号同步。

---

## 仓库结构

```
mianshi-zhilian-app/
├── apps/client/                    # Flutter 客户端（主代码库）
│   ├── lib/
│   │   ├── main.dart               # 应用入口，MultiProvider 注入
│   │   ├── generated/              # ⚠️ 自动生成，禁止手改（app_version.g.dart）
│   │   ├── l10n/                   # 自定义 i18n（l10n.dart + check_l10n_keys.py）
│   │   ├── models/                 # 数据模型
│   │   ├── pages/                  # auth / learning / practice / prep / mastery / profile + learning_shell.dart
│   │   ├── providers/              # 10 个 Provider（见下）
│   │   ├── services/               # 25 个服务（见下）
│   │   ├── theme/                  # 4 套内置主题 + 自定义
│   │   ├── utils/
│   │   └── widgets/
│   ├── android/  macos/  windows/  web/    # 平台壳（无 ios/）
│   ├── test/                       # 包含 integration/ 业务端到端测试
│   ├── tool/generate_version.sh    # 生成版本文件
│   ├── pubspec.yaml                # 版本号在此定义
│   └── analysis_options.yaml
├── workers/api/                    # Cloudflare Pages Functions
│   ├── src/                        # _worker.js / index.ts + 路由
│   ├── test/                       # vitest 测试
│   ├── tools/  scripts/            # 工具与 check-db-schema.mjs
│   ├── init-db.sql                 # D1 初始化 SQL（迁移覆盖检查依据）
│   ├── wrangler.toml               # 含 PLACEHOLDER_KV_NAMESPACE_ID / PLACEHOLDER_DATABASE_ID
│   └── wrangler-staging.toml
├── docs/                           # 设计与运维文档
│   ├── design.md                   # 完整开发设计方案
│   ├── deploy.md                   # 部署说明
│   ├── update.md                   # 软件更新机制
│   ├── data-storage-and-sync.md    # 存储与同步白名单
│   ├── privacy-policy.md           # 隐私政策
│   ├── testing.md                  # 测试策略
│   ├── voice-chunk-pipeline.md     # 语音分片管线
│   └── sponsor.md
├── scripts/
│   ├── pre-commit-check.sh         # ⭐ 提交前 8 步检查（必跑）
│   ├── auto-release.sh             # 发版自动化
│   ├── build_update_manifest.dart  # 生成 update.json
│   └── verify_release_assets.sh    # 校验发布资产
└── .github/workflows/              # ci / deploy-web / deploy-worker / release / cleanup-preview / codeql
```

### Providers（`apps/client/lib/providers/`，共 10 个）

| Provider | 职责 |
|---|---|
| `auth_provider` | 用户认证、登录/注册/登出 |
| `content_provider` | 知识路线与 topic 内容（按领域懒加载） |
| `progress_provider` | 学习进度、掌握度、练习记录 |
| `ai_provider` | 多 AI 配置、模型能力测试 |
| `settings_provider` | 应用设置、同步目标、偏好 |
| `localization_provider` | 中英文响应式切换 |
| `theme_provider` | 主题切换 |
| `connectivity_provider` | 网络状态 |
| `learning_scope_provider` | 学习路线作用域 |
| `update_download_provider` | 更新下载状态 |

### Services（`apps/client/lib/services/`，共 25 个 + `on_device_stt/` 子目录）

关键服务：
- `storage_service.dart` — **shared_preferences**，sqflite 已移除；敏感凭证走 `credential_store.dart` + `flutter_secure_storage`
- `ai_service.dart` — AI 流式调用、评估
- `data_sync_service.dart` — file/WebDAV/GitHub/Gitee 同步，**白名单快照**
- `content_api_service.dart` — 双源 fallback 拉取知识内容
- `endpoint_fallback_client.dart` — 主备 URL 自动切换的 HTTP 客户端
- `route_resolver.dart` / `route_composer.dart` / `route_state_store.dart` — 路线选择与持久化
- `update_service.dart`(+`_io`/`_stub`) — 更新检查与 SHA256 校验，条件导入
- `download_source_resolver.dart` — 下载源解析（含 ghproxy 镜像）
- `analytics_service.dart` / `app_log_service.dart` — 埋点与日志
- `privacy_service.dart` / `sensitive_data_redactor.dart` — 隐私与脱敏
- `app_permission_service.dart` / `app_version_service.dart` / `device_info_helper.dart` / `ticket_service.dart` / `whisper_migration_helper.dart` / `ai_route_generator.dart` / `api_headers.dart` / `api_response.dart`

### 练习模式（`apps/client/lib/pages/practice/`）

8 种：今日复习、复述、追问、薄弱点训练、高频冲刺、项目深挖、系统设计、模拟面试。

---

## 构建与运行

### 前置条件

- Flutter SDK `^3.11.5`（Dart 同梱）
- Node.js 22+（Worker / 用户机器为 v22.19.0，路径 `/usr/local/bin/node`）
- Python 3（仅用于 `check_l10n_keys.py`）

### Flutter 客户端（`apps/client/`）

```bash
flutter pub get                          # 安装依赖
bash tool/generate_version.sh            # 生成 lib/generated/app_version.g.dart 和 web/version.json
flutter run -d chrome                    # Web
flutter run -d macos                     # macOS
flutter analyze --no-fatal-infos         # 静态分析
python3 lib/l10n/check_l10n_keys.py      # l10n key 一致性
flutter test                             # 全部测试
flutter test test/integration/           # 业务端到端（真实 content 管线）
flutter test test/path/to_test.dart      # 单个测试
flutter build web --release              # Web 构建
```

**测试策略**（详见 `docs/testing.md`）：以 **业务/数据层端到端测试** 为主，使用 `test/fixtures/content_full/`（3 领域真实内容） + `FakeContentClient` 驱动真实的 `ContentApiService` / `ContentProvider`，**不是 mock**。完整页面 widget 测试只覆盖关键小控件（test/widget/），全页 widget 在测试视口下排版易碎。**Content（domains/topics/learningPaths/ids）是唯一事实来源**，测试必须用 content-shaped 数据。

### Worker（`workers/api/`）

```bash
cd workers/api
npm install
npm run dev               # = wrangler pages dev src/
npm run typecheck         # = tsc --noEmit
npm run check:migrations  # 校验 init-db.sql 覆盖所有迁移
npm test                  # = vitest run
npm run deploy            # 通常由 CI 触发，本地少用
```

### ⭐ 提交前检查（仓库根运行，必做）

```bash
./scripts/pre-commit-check.sh
```

**8 步**（注意：README/CLAUDE.md 旧文档说 7 步，**以脚本实际为准**）：
1. `flutter pub get`
2. `bash tool/generate_version.sh`
3. `python3 lib/l10n/check_l10n_keys.py`
4. `flutter analyze --no-fatal-infos`
5. `flutter test`
6. `flutter build web --release`
7. `npm run --prefix workers/api check:migrations`（D1 迁移覆盖）
8. `npm run --prefix workers/api typecheck` + `npm test --prefix workers/api`

不要跳过。CI 也跑同一套，本地先过能省一轮 push。

---

## 开发约定

### 版本号管理

- `apps/client/pubspec.yaml` 中 `version: x.y.z+BUILD`（当前 `0.1.7+174`）
- **`BUILD` 必须单调递增**——Android `versionCode` 不允许降级，发版会失败
- 发布 tag `vx.y.z` 必须与 pubspec 中的语义版本一致
- 改完版本号后必须 `bash tool/generate_version.sh`，否则 `lib/generated/app_version.g.dart` 与运行时不一致

### Commit 规范（中文，遵循 `.gitmessage`）

格式：`<type>: <中文描述>`，一行写完，不要 body 段落。

| Type | Release notes 分组 |
|---|---|
| `feat` | ✨ 新功能 |
| `fix` | 🐛 问题修复 |
| `docs` | 📝 文档更新 |
| `refactor` / `perf` / `test` / `chore` | 🔧 其他改动 |
| `ci` / `revert` / `merge` | **不进 release notes** |

原则：
- 描述聚焦"为什么做"和"做了什么"，不写实现细节——release notes 直接复用 commit 描述
- **不要加 `Co-authored-by: Qwen-Coder` 之类的合作者行**
- CI 调参用 `ci:`，回退用 `revert:`，合并用 `merge`，这三类不会让用户在更新弹窗看到

示例：
```
feat: 掌握度看板支持按月筛选
fix: 登录页键盘弹起后按钮被遮挡
chore: 构建号 173→174
ci: 添加 pub-cache 缓存加速依赖安装
```

### 国际化（L10n）

- 自定义静态类方案，**非 flutter_intl/easy_localization**
- 文件：`apps/client/lib/l10n/l10n.dart`（`_zh` / `_en` 两套 map）
- Key 为英文 `snake_case`，**不能含中文/Unicode/参数占位符**
- `get(key, lang)` fallback 链：中文 → 英文 → key 本身；`getp(...)` 模板插值 `{param}`
- **UI 中禁止硬编码中文展示文本**，所有 chrome 文案必须 `l10n.get()`
- 维护：`python3 lib/l10n/check_l10n_keys.py`（提交前自动运行）
- 切换：`LocalizationProvider` 响应式

### 数据架构与隐私

- **本地优先**：学习记录、AI 配置、设置默认存本地
- **同步采用白名单快照**——`data_sync_service.dart` 只导出显式列入白名单的字段。**新增字段时必须主动决定是否进入同步**
- **API Key 永远不出现在导出、同步 payload、日志中**
- 敏感凭证（AI API Key、记住的登录密码）走 `flutter_secure_storage`（Keychain/Keystore/DPAPI），**绝不能挪回明文 SharedPreferences**
- Worker API 职责：用户认证、工单、访问统计、安全限制、代理 update.json

### 内容缓存

| Key | 含义 |
|---|---|
| `content_version` | 当前已知内容版本 |
| `content_version_pending` | 待刷新版本 |
| `domain_cache_{domainId}` | 领域知识点缓存 |
| `domain_version_{domainId}` | 该领域缓存对应的版本 |

启动 → manifest 检查 contentVersion → 有变化记 pendingVersion → 切换领域时按需加载新内容。

### 语音识别（STT）

5 种模式：`auto`（默认，按优先级回退）/ `follow_current_ai` / `fixed_ai_config` / `system` / `sherpa_onnx`。

平台约束：
- **Web 不支持 `dart:ffi`**，sherpa_onnx 不可用；也无系统语音兜底，必须依赖可转写 AI
- macOS 系统语音稳定；无 GMS 的 Android 回退 sherpa_onnx 或可用 AI
- `on_device_stt_factory.dart` 用 `export if (dart.library.io)` 条件导出，原生导出真实实现，Web 导出空桩

sherpa_onnx 模型采用 **archive (.tar.bz2) 下载 + 解压** 方式，不是 per-file。

### Cloudflare Worker 部署细节

- 部署形态是 **Cloudflare Pages Functions**，不是独立 Worker
- `wrangler.toml` 中 `PLACEHOLDER_KV_NAMESPACE_ID` / `PLACEHOLDER_DATABASE_ID` 会被 CI 通过 `sed` 从 GitHub Secrets 替换。**不要把真实 ID 提交到仓库**
- `JWT_SECRET` 在 Cloudflare Pages Dashboard 配置，不进 `wrangler.toml`
- 内容来源在 `[vars]` 配置主备两个 CDN origin

### CI/CD

| Workflow | 触发 | 行为 |
|---|---|---|
| `ci.yml` | PR / main push | analyze + test + build web |
| `deploy-web.yml` | main push（apps/client 变更） | Cloudflare Pages |
| `deploy-worker.yml` | main push（workers/api 变更） | Pages Functions |
| `release.yml` | tag `v*` push | 并行构建 Android / Windows / macOS / Web → GitHub Releases |
| `cleanup-preview.yml` | PR 关闭 | 清理 preview 部署 |
| `codeql.yml` | 定时 + push | 安全扫描 |

GitHub Secrets：`CLOUDFLARE_API_TOKEN`、`D1_DATABASE_ID`、`JWT_SECRET`
GitHub Variables：`CLOUDFLARE_ACCOUNT_ID`
Android release 可选签名 secrets：`ANDROID_RELEASE_KEYSTORE_BASE64` / `STORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`，未配置时回退 debug signing。

### 发布流程

```bash
# 1. 改 apps/client/pubspec.yaml 版本号（buildNumber 必须递增）
# 2. 提交
git add -A && git commit -m "chore: 构建号 N→N+1"
git push origin main
# 3. 打 tag
git tag -a vx.y.z -m "Release vx.y.z"
git push origin vx.y.z
# 4. release.yml 自动多平台构建并发布到 GitHub Releases
```

或用 `scripts/auto-release.sh` 自动化。

---

## 与 Qwen Code 协作的特别约定

> 这些约定来自历史协作偏好，对本仓库长期有效。

1. **诊断优先**：遇到问题先系统性分析所有相关防护层/链路/路径再动手，不要跳过诊断直接改代码。
2. **不要在 commit 里加 `Co-authored-by`**，包括 Qwen-Coder 或任何 AI 合作者标记。
3. **推送构建无需二次确认**：用户说"推送构建/发版"就直接执行 `commit-push` / `release-build` / `release-new-version` 流程，不要弹确认框。
4. **域名不可达用重试兜底**，不引入代理方案；`pages.dev` 是 SPA，不是二进制下载源；更新下载镜像前缀是 `ghproxy.com`。
5. **Skill 是顾问不是执行者**：项目 skill 给建议，主 agent 自己按业务边界推进；不要让 skill 自动分块/拆分内容。
6. **Release notes 聚焦用户可感知变更**，而非幕后基础设施改动。
7. **README 的"直接使用"链接指向 Web App（pages.dev）**，不是官网落地页。
8. **建议输出为可直接复制粘贴的连续文本提示词**，不用表格或多级列表罗列动作项。
9. 修改 `~/.qwen/settings.json` 时**不要改模型 provider 的 `id` 字段**——`model.name` 按 id 匹配，改 id 会破坏配置；切换默认模型应调整顺序或改 `model.name`。

---

## 设计理念

- **不花哨，像一个认真备战面试的控制台**
- 内容密度高、结构清楚、状态反馈明确
- 卡片承载知识点、掌握状态、AI 反馈
- 大面积页面区块保持干净、可扫描
- 支持游客模式 → 登录后迁移本地进度
- 用户自带 API Key，平台不承担 AI 调用成本
