# 面试智练 - Flutter 客户端

面试智练的跨平台客户端，基于 Flutter 构建，支持 Web、Android、macOS、Windows。

## 技术栈

- **框架**: Flutter 3.41+
- **状态管理**: Provider
- **本地存储**: SharedPreferences
- **网络**: http 包 + 自定义 AI/STT 服务
- **语音识别**: record 录音 + Whisper STT
- **数据同步**: WebDAV + Worker API

## 项目结构

```
lib/
├── main.dart                    # 应用入口、路由、Provider 注册
├── models/                      # 数据模型
│   ├── app_settings.dart        # 应用设置模型
│   ├── user.dart                # 用户模型
│   └── ...
├── pages/                       # 页面
│   ├── learning/                # 学习模块（目录、详情、仪表盘）
│   ├── practice/                # 练习模块（复述、追问、模拟面试、系统设计）
│   ├── mastery/                 # 掌握度看板
│   ├── prep/                    # 面试准备（JD 解析、训练计划）
│   ├── profile/                 # 个人中心（AI 配置、主题、数据管理）
│   └── auth/                    # 登录注册
├── providers/                   # 状态管理
│   ├── ai_provider.dart         # AI 配置和请求状态
│   ├── auth_provider.dart       # 认证状态
│   ├── progress_provider.dart   # 学习进度和掌握度
│   └── settings_provider.dart   # 设置和 WebDAV 同步
├── services/                    # 服务层
│   ├── ai_service.dart          # AI API 调用（流式/非流式）
│   ├── storage_service.dart     # 本地数据存储和导出
│   ├── webdav_sync_service.dart # WebDAV 备份/恢复
│   ├── whisper_stt_service.dart # Whisper 语音转文字
│   └── update_service.dart      # OTA 更新检查
├── widgets/                     # 通用组件
│   ├── voice_input_button.dart  # 语音输入按钮
│   ├── header_bar.dart          # 顶部导航栏
│   └── ...
├── utils/                       # 工具类
│   ├── platform_file_reader.dart      # 跨平台文件读取（条件导出）
│   ├── platform_file_reader_io.dart   # dart:io 实现
│   └── platform_file_reader_stub.dart # Web 平台桩实现
└── theme/                       # 主题配置
    └── colors.dart              # 颜色常量和内置主题
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
- **Web 语音**: Whisper STT 暂不支持 Web 端，会降级为文本输入
- **临时文件**: 使用 `path_provider` 获取平台临时目录，不硬编码路径
