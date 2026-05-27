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

App 会按最新 manifest/domain 引用裁剪本地 topic 缓存。内容平台删除并发布后的知识点，不会继续留在本地缓存里。

## 当前学习体验

- 学习首页展示领域选择、当前掌握度、继续学习和学习节奏。
- 领域目录提供两个入口：`知识查阅` 打开知识学习 Tab，`学习模式` 直接进入复述练习 Tab。
- 知识详情按内容仓库的 learningCards 渲染解释、机制拆解、对比表、图示占位、代码片段、面试回答模板和 checklist。
- 复述练习根据 recallPrompts 和 rubric 进行 AI 评估并更新本地掌握度。
