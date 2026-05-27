# 面试智练 App

面试智练正式客户端仓库，包含 Flutter 多端 App、Cloudflare Worker API 和自动发布脚本。

## 结构

- `apps/client`：Flutter Web / Android / macOS / Windows 客户端。
- `workers/api`：Cloudflare Worker API，提供健康检查、配置、AI 代理和同步接口占位。
- `scripts`：发布与 update manifest 工具。
- `.github/workflows`：CI、Release、Web 部署和 Worker 部署。

## 本地运行

```bash
cd apps/client
flutter pub get
flutter run
```

## 内容源

默认内容仓库为 `nontracey/mianshi-zhilian-content`，正式 App 读取 `manifest.json`，测试模式可读取 `staging-manifest.json`。
