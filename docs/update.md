# 软件更新

面试智练支持应用内手动检查更新和下载安装包功能。

## 更新机制

### 检查更新流程

```
用户点击"检查更新"
       ↓
请求 update.json（默认走 Cloudflare Worker 代理 GitHub Release）
       ↓
对比 version 和 buildNumber
       ↓
有新版本 → 显示更新内容和文件大小
       ↓
用户确认 → 依次尝试下载源：
  GitHub 官方 → 用户自定义镜像 → ghproxy.com → manifest 中的其他镜像
       ↓
校验 sha256 → 引导安装
       ↓
所有源失败 → 提示"网络无法连接，请检查网络或配置镜像站"
```

### update.json 格式

```json
{
  "version": "0.1.0",
  "buildNumber": 100,
  "releaseDate": "2026-05-27",
  "notes": [
    "新增领域知识目录",
    "新增 AI 复述评估",
    "优化掌握度排序"
  ],
  "platforms": {
    "android": {
      "url": "https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-android.apk",
      "mirrors": [
        "https://ghproxy.com/https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-android.apk"
      ],
      "sha256": "abc123...",
      "size": 52428800
    },
    "windows": {
      "url": "https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-windows-setup.exe",
      "sha256": "def456...",
      "size": 73400320
    },
    "macos": {
      "url": "https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-macos.dmg",
      "sha256": "ghi789...",
      "size": 83886080
    },
    "web": {
      "url": "https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-web.zip",
      "sha256": "jkl012...",
      "size": 10485760
    }
  }
}
```

## Release 工作流

`Release` workflow 会在 tag 发布时自动生成以下资产：

| 文件 | 说明 |
|------|------|
| `mianshi-zhilian-vX.Y.Z-android.apk` | Android 安装包 |
| `mianshi-zhilian-vX.Y.Z-windows-setup.exe` | Windows 安装程序 |
| `mianshi-zhilian-vX.Y.Z-windows.zip` | Windows 便携版 |
| `mianshi-zhilian-vX.Y.Z-macos.dmg` | macOS 安装镜像 |
| `mianshi-zhilian-vX.Y.Z-macos.zip` | macOS 便携版 |
| `mianshi-zhilian-vX.Y.Z-web.zip` | Web 静态文件 |
| `update.json` | 更新清单（含 sha256、size 和镜像地址） |

### 构建策略

- 各平台并行构建，不等待全部完成
- 单个平台构建完成后立即上传到 GitHub Release
- 所有平台完成后生成并上传 `update.json`
- `update.json` 中的 `mirrors` 默认包含 `ghproxy.com` 加速镜像；可通过 CI 环境变量 `GH_MIRROR_PREFIX` 追加自定义镜像

## 下载源与镜像机制

客户端下载更新时按以下顺序依次尝试：

| 优先级 | 下载源 | 说明 |
|--------|--------|------|
| 1 | GitHub 官方 | `update.json` 中的 `url` 字段，默认首选 |
| 2 | 用户自定义镜像 | 在"关于与更新"页 ⚙️ 设置中配置的前缀，拼接到 GitHub URL 前面 |
| 3 | ghproxy.com | 内置备用镜像，自动加速 GitHub Release 下载 |
| 4 | manifest 中的其他镜像 | `update.json` `mirrors` 字段中的额外地址 |

- 某个源下载失败后自动尝试下一个，用户在进度对话框中能看到当前正在从哪个源下载
- 校验失败（sha256 不匹配）不会重试其他源，直接报错
- 所有源都失败时提示"网络无法连接，请检查网络或配置 GitHub 镜像站后重试"

### 用户自定义镜像站

用户可以在 **个人中心 → 关于与更新 → ⚙️ 下载设置** 中配置自定义 GitHub 镜像站前缀（如 `https://ghproxy.com`）。配置后该镜像会排在 GitHub 官方之后、内置备用镜像之前。留空则仅使用默认的下载源顺序。

## 平台更新策略

| 平台 | MVP 策略 | 正式策略 |
|------|---------|---------|
| Web | 刷新即更新 | Cloudflare Pages 自动更新 |
| Android | 下载 APK，用户确认安装 | 首次安装第三方 APK 时可能需要系统授权"允许安装未知应用"；后续可接应用商店 |
| Windows | 下载 exe/zip，引导安装 | MSIX App Installer |
| macOS | 下载 dmg/zip，引导安装 | 后续可做 Sparkle 自动更新 |

## 版本规则

- 使用 SemVer：`major.minor.patch`
- `buildNumber` 用于同版本内部构建递增
- `minimumRequiredVersion` 大于当前版本时提示强制更新
- 非强制更新由用户决定是否安装

## 稳定更新地址

客户端默认使用 `RouteResolver.appApi + /update.json`。Pages Functions 会代理 GitHub latest release 中的 `update.json`，避免客户端直接依赖 GitHub API：

```
https://mianshi-zhilian-api.pages.dev/update.json
https://mianshizhilian-api.nontracey.de5.net/update.json
```

生产构建不再支持通过 `UPDATE_MANIFEST_URL` 固定官方更新域名；官方主备域名由客户端路由表统一维护。

Worker 只代理体积很小的 `update.json`。各平台安装包不会经过 Worker 转发；客户端会优先使用 `assetPath` 生成官方 Web 主备下载候选，再依次尝试 GitHub Release、用户自定义镜像和默认镜像源。

## 隐私说明

检查更新只发起匿名 `GET update.json` 请求，不会主动上传账号、设备 ID、学习数据或当前版本号。和所有网络请求一样，Cloudflare/GitHub 仍会接收到基础网络元数据，例如 IP 和 User-Agent。

下载安装包后，客户端会先校验 `sha256`，校验通过才启动系统安装流程。Android 如果未授权安装第三方 APK，会在用户点击安装时提示并引导前往系统设置开启权限；该授权只影响系统安装器，不会授予 App 读取用户学习数据的额外能力。

## 代码实现

### UpdateService

```dart
class UpdateService {
  final String updateManifestUrl;
  final String? customMirrorPrefix; // 用户自定义镜像站前缀

  /// 下载结果枚举，区分失败原因
  // DownloadResult { success, networkError, verificationFailed, cancelled }

  /// 构建下载 URL 列表：GitHub → 自定义镜像 → ghproxy → manifest mirrors
  List<String> _buildDownloadUrls(PlatformUpdate platformUpdate) { ... }

  /// 下载更新，返回 (文件路径, DownloadResult)
  Future<(String?, DownloadResult)> downloadUpdate({ ... }) { ... }

  Future<UpdateInfo?> checkForUpdate(AppBuildInfo currentVersion) async { ... }
  PlatformUpdate? getPlatformUpdate(UpdateInfo updateInfo) { ... }
}
```

### 个人中心集成

```dart
// 关于与更新页面
// - 点击"检查更新"行 → 检查并下载更新
// - 点击 ⚙️ 图标 → 打开下载设置弹窗（配置自定义镜像站）
final updateService = UpdateService(
  customMirrorPrefix: settings.customGithubMirror,
);
final updateInfo = await updateService.checkForUpdate(currentVersion);
```
