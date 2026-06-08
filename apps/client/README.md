# 面试智练 - Flutter 客户端

面试智练的跨平台客户端，基于 Flutter 构建，支持 Web、Android、macOS、Windows。

## 技术栈

- **框架**: Flutter 3.41+
- **状态管理**: Provider + 按领域拆分的 ChangeNotifier
- **路由**: GoRouter（27 条声明式路由）
- **本地存储**: SharedPreferences
- **网络**: http 包 + 自定义 EndpointFallbackClient（主备路线自动回退）
- **语音识别**: record 录音 + 云端 AI 语音 / 系统语音 / sherpa-onnx 本机 STT
- **系统权限**: permission_handler + 平台权限声明
- **数据同步**: WebDAV + GitHub + Gitee（自动同步每 30 秒检测）
- **语音识别**: record 录音 + 云端 AI 语音 / 系统语音 / sherpa-onnx 本机 STT
- **系统权限**: permission_handler + 平台权限声明
- **数据同步**: WebDAV + Worker API

## 项目结构

```
lib/
├── main.dart                    # 应用入口、GoRouter 路由表、Provider 注册
├── pages/
│   ├── learning_shell.dart      # 主导航壳（6个 section 切换）
│   ├── learning/                # 学习模块
│   │   ├── dashboard_page.dart  # 学习工作台首页
│   │   ├── dashboard_panels.dart# 三栏面板组件
│   │   ├── dashboard_widgets.dart# 掌握度/知识卡片组件
│   │   ├── dashboard_dialogs.dart# 路线选择/领域管理弹窗
│   │   ├── catalog_page.dart    # 领域知识目录
│   │   ├── topic_detail_page.dart# 知识点详情页
│   │   ├── topic_detail_cards.dart# 学习卡片组件（解释/代码/表格/图示）
│   │   └── topic_detail_panels.dart# 详情页面板组件
│   ├── practice/                # 练习模块
│   │   ├── recall_page.dart     # 复述练习
│   │   ├── recall_panels.dart   # 复述练习面板组件
│   │   ├── mock_interview_page.dart # 模拟面试
│   │   ├── mock_interview_widgets.dart
│   │   ├── practice_page.dart   # 练习首页
│   │   ├── practice_widgets.dart# 练习首页组件
│   │   ├── follow_up_training_page.dart # 追问训练
│   │   ├── today_review_page.dart # 今日复习
│   │   ├── today_review_widgets.dart
│   │   ├── weakness_training_page.dart # 薄弱知识训练
│   │   ├── high_frequency_sprint_page.dart # 高频知识冲刺
│   │   ├── answer_template_page.dart # 回答模板
│   │   ├── answer_template_widgets.dart
│   │   ├── answer_versions_page.dart # 回答版本库
│   │   ├── system_design_page.dart # 系统设计
│   │   ├── project_dig_page.dart # 项目深挖
│   │   └── ...
│   ├── mastery/                 # 掌握度看板
│   ├── prep/                    # 面试准备（JD 解析、训练计划、项目库）
│   ├── profile/                 # 个人中心
│   │   ├── profile_page.dart    # 个人中心首页
│   │   ├── sync_backup_page.dart# 同步与备份
│   │   ├── ai_voice_settings_page.dart # AI 与语音配置
│   │   ├── learning_preferences_page.dart # 学习偏好
│   │   ├── appearance_language_page.dart # 外观与语言
│   │   ├── content_source_page.dart # 知识源配置
│   │   ├── route_preference_page.dart # 线路诊断
│   │   ├── about_update_page.dart # 关于与更新
│   │   ├── ai_config_page.dart  # AI 模型配置
│   │   ├── log_management_page.dart # 日志管理
│   │   └── on_device_model_management_page.dart # 本机模型管理
│   └── auth/                    # 登录注册
│       ├── login_page.dart
│       ├── change_password_page.dart
│       └── submit_ticket_page.dart
├── l10n/                       # 国际化
│   ├── l10n.dart                # 中英文翻译映射（1519 key）
│   └── check_l10n_keys.py       # key 一致性校验脚本
├── providers/                   # 状态管理
│   ├── settings_provider.dart   # 应用设置
│   ├── theme_provider.dart      # 主题状态（与 SettingsProvider 分离，避免全树重建）
│   ├── connectivity_provider.dart # 网络连通性
│   ├── localization_provider.dart # 语言切换
│   ├── content_provider.dart    # 知识内容加载和缓存
│   ├── progress_provider.dart   # 学习进度和掌握度
│   ├── ai_provider.dart         # AI 配置和评估
│   └── auth_provider.dart       # 认证状态（JWT 刷新、token 管理）
├── services/                    # 服务层
│   ├── api_response.dart        # API 响应安全解析
│   ├── ai_service.dart          # AI API 调用（流式/非流式评估）
│   ├── storage_service.dart     # 本地数据存储和导出
│   ├── data_sync_service.dart   # 多后端同步（WebDAV/GitHub/Gitee）
│   ├── endpoint_fallback_client.dart # HTTP 主备路线自动回退
│   ├── route_resolver.dart      # 路线解析（主站/备站域名）
│   ├── route_state_store.dart   # 路线状态持久化
│   ├── download_source_resolver.dart # 下载镜像源自动选择
│   ├── whisper_migration_helper.dart # 旧版 Whisper 配置迁移
│   ├── privacy_service.dart     # AI 上传前隐私确认
│   ├── app_permission_service.dart # 相机/相册/麦克风权限引导
│   ├── app_log_service.dart     # 本地日志
│   ├── app_version_service.dart # 版本号解析
│   ├── analytics_service.dart   # 使用统计
│   ├── ticket_service.dart      # 工单提交
│   ├── update_service.dart      # 检查更新和安装包校验
│   └── on_device_stt/           # sherpa-onnx 本机语音识别与资源下载
├── widgets/                     # 通用组件
│   ├── header_bar.dart          # 顶部导航栏
│   ├── header_bar_widgets.dart  # 导航栏子组件（AI模型选择器/内容环境选择器）
│   ├── navigation_rail_panel.dart # 侧边导航栏
│   ├── offline_banner.dart      # 离线提示横幅
│   ├── onboarding_screen.dart   # 新用户引导
│   ├── voice_input_button.dart  # 语音输入按钮
│   ├── work_panel.dart          # 通用工作面板容器
│   ├── privacy_dialog.dart      # 隐私确认弹窗
│   └── ...
├── models/                      # 数据模型
│   ├── app_settings.dart        # 应用设置（28个字段）
│   ├── user_progress.dart       # 练习进度/尝试/会话/同步设置
│   ├── ai_config.dart           # AI 模型配置
│   ├── topic.dart               # 知识点模型
│   ├── domain.dart              # 领域模型
│   ├── user.dart                # 用户模型
│   └── ...
├── theme/                       # 主题配置
│   └── colors.dart              # 颜色常量和内置主题
└── generated/                   # CI 自动生成
    ├── app_version.g.dart
    └── release_notes.dart

## 测试

```
test/
├── providers/                   # Provider 单元测试
│   ├── ai_provider_test.dart
│   ├── auth_provider_test.dart
│   ├── content_provider_test.dart
│   ├── progress_provider_test.dart
│   ├── settings_provider_test.dart
│   └── theme_provider_test.dart
├── services/                    # 服务层测试
│   ├── api_response_test.dart
│   ├── analytics_buffer_test.dart
│   ├── app_version_service_test.dart
│   ├── content_api_service_test.dart
│   ├── endpoint_fallback_client_test.dart
│   ├── route_resolver_test.dart
│   ├── storage_service_test.dart
│   ├── storage_sync_package_test.dart
│   ├── update_service_test.dart
│   └── whisper_migration_helper_test.dart
├── models/                      # 模型序列化测试
│   ├── app_settings_test.dart
│   ├── topic_test.dart
│   └── user_progress_test.dart
├── pages/                       # 页面 Widget 测试
│   └── ai_config_page_test.dart
└── widget_test.dart             # 应用冒烟测试
```

## 路由

使用 GoRouter 声明式路由（定义在 `main.dart`），共 27 条：

| 路由 | 目标页面 |
|------|---------|
| `/` | LearningShell / OnboardingScreen |
| `/topic` | TopicDetailPage |
| `/practice/recall` | RecallPage |
| `/practice/mock-interview` | MockInterviewPage |
| `/practice/today-review` | TodayReviewPage |
| `/practice/weakness-training` | WeaknessTrainingPage |
| `/practice/follow-up-training` | FollowUpTrainingPage |
| `/practice/system-design` | SystemDesignPage |
| `/practice/project-dig` | ProjectDigPage |
| `/practice/high-frequency` | HighFrequencySprintPage |
| `/practice/answer-versions` | AnswerVersionsPage |
| `/auth/login` | LoginPage |
| `/auth/change-password` | ChangePasswordPage |
| `/auth/submit-ticket` | SubmitTicketPage |
| `/profile/ai-config` | AiConfigPage |
| `/profile/log-management` | LogManagementPage |
| `/profile/model-management` | OnDeviceModelManagementPage |
| `/profile/sync-backup` | SyncBackupPage |
| `/profile/ai-voice-settings` | AiVoiceSettingsPage |
| `/profile/learning-preferences` | LearningPreferencesPage |
| `/profile/appearance-language` | AppearanceLanguagePage |
| `/profile/content-source` | ContentSourcePage |
| `/profile/route-preference` | RoutePreferencePage |
| `/profile/about-update` | AboutUpdatePage |

所有 `Navigator.of(context).push(MaterialPageRoute(...))` 已迁移为 `context.push('path', extra: widget)`。`showDialog` 保持不变。

## 网络架构

- **主备路线回退**：`EndpointFallbackClient` 自动在 pages.dev ↔ de5.net 之间选择可用路线
- **流量感知**：`ConnectivityProvider` 监听网络状态，离线时显示 `OfflineBanner`
- **内容 CDN**：知识内容走 Cloudflare Pages，客户端按 manifest 版本增量更新
- **下载镜像**：`DownloadSourceResolver` 自动选择最快线路（GitHub → 自定义镜像 → ghfast.top → 清单镜像）

## 关键架构决策

| 决策 | 说明 |
|------|------|
| **ThemeProvider 分离** | 主题状态从 SettingsProvider 拆出，MaterialApp 只监听主题变更，改语言/领域不触发全树重建 |
| **GoRouter 路由** | 27 条声明式路由，支持 deep link 扩展；push 调用统一走 context.push |
| **God Page 解耦** | 5 个大文件从 13,237 行缩减到 4,298 行（-67%），提取 22 个组件文件 |
| **API 安全解析** | ApiResponse 包装类统一处理 JSON 解析、类型校验、success 字段检查 |
| **主备域名交换** | de5.net 改为主站（更低延迟），pages.dev 改为备站 |
```

## 本地运行

### 前置条件

- Flutter SDK 3.41+
- 如需构建桌面端，需安装对应平台工具链

### 启动

```bash
# 获取依赖
flutter pub get

# Web
flutter run -d chrome

# macOS
flutter run -d macos

# Android（需连接设备或启动模拟器）
flutter run -d android
```

### 提交前检查

```bash
# 在项目根目录运行
./scripts/pre-commit-check.sh
```

## 平台兼容说明

- **Web**: 不支持 `dart:io`，使用 `platform_file_reader.dart` 条件导出处理
- **Web 语音**: 本机 STT 暂不支持 Web 端；Web 端需要配置可用的云端 AI 语音能力，否则降级为文本输入。
- **本机语音**: sherpa-onnx 本机识别需要同时下载 ONNX Runtime 和所选模型；资源下载支持自动选择最快线路、暂停、取消、断点续传、速度显示和独立删除。
- **临时文件**: 使用 `path_provider` 获取平台临时目录，不硬编码路径
- **系统权限**: 语音、拍照、相册、Android 安装包会在用户触发功能时请求权限；拒绝或永久拒绝后提示用户前往系统设置授权。
- **Android 权限声明**: `AndroidManifest.xml` 声明网络、安装 APK、麦克风、相机和图片读取权限。
- **macOS 权限声明**: `Info.plist` 声明相机、麦克风、相册、语音识别用途；沙盒 entitlements 开启相机和麦克风。
