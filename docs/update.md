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
用户确认 → 下载对应平台安装包
       ↓
校验 sha256 → 引导安装
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
        "https://gitee.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.0/mianshi-zhilian-v0.1.0-android.apk"
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
| `update.json` | 更新清单（含 sha256 和 size） |

### 构建策略

- 各平台并行构建，不等待全部完成
- 单个平台构建完成后立即上传到 GitHub Release
- 所有平台完成后生成并上传 `update.json`
- 如果配置了 `GITEE_TOKEN`，CI 会把安装包和 `update.json` 同步到 Gitee Release；客户端弱网下载失败时会尝试 `mirrors` 备用地址

## 平台更新策略

| 平台 | MVP 策略 | 正式策略 |
|------|---------|---------|
| Web | 刷新即更新 | Cloudflare Pages 自动更新 |
| Android | 下载 APK，用户确认安装 | 首次安装第三方 APK 时可能需要系统授权“允许安装未知应用”；后续可接应用商店 |
| Windows | 下载 exe/zip，引导安装 | MSIX App Installer |
| macOS | 下载 dmg/zip，引导安装 | 后续可做 Sparkle 自动更新 |

## 版本规则

- 使用 SemVer：`major.minor.patch`
- `buildNumber` 用于同版本内部构建递增
- `minimumRequiredVersion` 大于当前版本时提示强制更新
- 非强制更新由用户决定是否安装

## 稳定更新地址

客户端默认使用 Cloudflare Worker 的稳定路径。Worker 会代理 GitHub latest release 中的 `update.json`，避免客户端直接依赖 GitHub API：

```
https://mianshi-zhilian-api.nontracey.workers.dev/update.json
```

也可以通过 `UPDATE_MANIFEST_URL` 编译参数改为其他稳定地址。

Worker 只代理体积很小的 `update.json`。各平台安装包不会经过 Worker 转发，客户端会直接请求 `update.json` 中的平台 `url`，失败后再依次尝试 `mirrors`，避免把 GitHub/Gitee Release 安装包下载流量计入 Cloudflare Worker。

## 隐私说明

检查更新只发起匿名 `GET update.json` 请求，不会主动上传账号、设备 ID、学习数据或当前版本号。和所有网络请求一样，Cloudflare/GitHub 仍会接收到基础网络元数据，例如 IP 和 User-Agent。

下载安装包后，客户端会先校验 `sha256`，校验通过才启动系统安装流程。Android 如果未授权安装第三方 APK，会在用户点击安装时提示并引导前往系统设置开启权限；该授权只影响系统安装器，不会授予 App 读取用户学习数据的额外能力。

## 代码实现

### UpdateService

```dart
class UpdateService {
  final String updateManifestUrl;

  Future<UpdateInfo?> checkForUpdate(AppBuildInfo currentVersion) async {
    final response = await http.get(Uri.parse(updateManifestUrl));
    final data = json.decode(response.body);
    final remoteVersion = data['version'];
    final remoteBuildNumber = data['buildNumber'];
    
    if (_isNewerVersion(
      remoteVersion: remoteVersion,
      remoteBuildNumber: remoteBuildNumber,
      localVersion: currentVersion.version,
      localBuildNumber: currentVersion.buildNumber,
    )) {
      return UpdateInfo.fromJson(data);
    }
    return null;
  }

  PlatformUpdate? getPlatformUpdate(UpdateInfo updateInfo) {
    if (kIsWeb) return null; // Web 端自动更新
    // 根据当前平台返回对应的更新信息
  }
}
```

### 个人中心集成

```dart
// 检查更新
final updateService = UpdateService();
final updateInfo = await updateService.checkForUpdate(currentVersion);

if (updateInfo != null) {
  // 显示更新对话框
  showDialog(...);
}
```
