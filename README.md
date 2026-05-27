# 面试智练 App

面试智练是一款 AI 主动回忆学习工作台，通过"知识学习 → 主动复述 → AI 评估纠错 → 掌握度更新"帮助用户系统备战技术面试。

## 功能特性

### 学习模块
- **学习首页**：领域选择、当前掌握度、继续学习入口
- **领域知识目录**：按分类展示知识点，支持知识查阅和学习模式
- **知识点详情**：Markdown 渲染、代码语法高亮、图解展示
- **复述练习**：文本/语音输入，AI 评估纠错
- **模拟面试**：连续多题模式，模拟真实面试场景

### 掌握度系统
- **本地掌握度记录**：按领域独立记录
- **掌握度看板**：按领域切换、熟练度排序
- **今日复习**：基于遗忘曲线的复习队列

### AI 配置
- **多配置支持**：支持多个 AI 服务配置
- **Web AI 代理**：Web 端通过 Worker 代理解决 CORS 限制
- **测试连接**：配置后可测试连接是否正常

### 用户系统
- **用户名密码登录**：支持注册登录
- **云端数据同步**：D1 数据库存储学习进度
- **数据合并**：登录后自动合并本地进度到云端
- **数据导出**：导出本地学习记录为 JSON 文件

### 个性化设置
- **主题设置**：浅色/深色模式、主色/强调色调整
- **语言设置**：中英文切换
- **学习推荐策略**：加权推荐、随机推荐、顺序推荐
- **检查更新**：自动检查新版本并提示更新

## 技术栈

| 模块 | 技术 |
|------|------|
| 客户端 | Flutter (Web/Android/macOS/Windows) |
| API | Cloudflare Workers |
| 数据库 | Cloudflare D1 |
| 内容 CDN | Cloudflare Pages |
| CI/CD | GitHub Actions |

## 项目结构

```
mianshi-zhilian-app/
├── apps/client/                 # Flutter 客户端
│   ├── lib/
│   │   ├── models/             # 数据模型
│   │   ├── pages/              # 页面
│   │   │   ├── learning/       # 学习相关页面
│   │   │   ├── practice/       # 练习相关页面
│   │   │   ├── mastery/        # 掌握度页面
│   │   │   ├── profile/        # 个人中心
│   │   │   └── auth/           # 登录注册
│   │   ├── providers/          # 状态管理
│   │   ├── services/           # 服务层
│   │   ├── widgets/            # 通用组件
│   │   └── theme/              # 主题配置
│   └── pubspec.yaml
├── workers/api/                 # Cloudflare Worker API
│   ├── src/index.ts            # API 路由和处理
│   └── wrangler.toml           # Worker 配置
├── scripts/                     # 构建脚本
└── .github/workflows/          # CI/CD 配置
```

## 本地运行

### 前置条件
- Flutter SDK 3.41+
- Node.js 22+

### 启动客户端
```bash
cd apps/client
flutter pub get
flutter run -d chrome  # Web
flutter run -d macos   # macOS
```

### 启动 Worker（可选）
```bash
cd workers/api
npm install
npx wrangler dev
```

## 部署

### 自动部署
推送到 `main` 分支会自动触发：
- `CI`：Flutter 分析和测试
- `Deploy web`：部署 Web 版本到 Cloudflare Pages
- `Deploy worker`：部署 Worker API

### 发布版本
```bash
# 更新版本号
# apps/client/pubspec.yaml: version: x.x.x+xxx

# 创建 tag
git tag -a vx.x.x -m "Release vx.x.x"
git push origin vx.x.x
```

会自动触发 `Release` 工作流，构建各平台安装包并上传到 GitHub Releases。

## 内容源

默认内容仓库：`nontracey/mianshi-zhilian-content`

内容通过 `manifest.json` 驱动，支持：
- 测试环境：`staging-manifest.json`
- 正式环境：`manifest.json`

## 相关仓库

| 仓库 | 说明 |
|------|------|
| [mianshi-zhilian-content](https://github.com/nontracey/mianshi-zhilian-content) | 知识内容仓库 |
| [mianshi-zhilian-content-studio](https://github.com/nontracey/mianshi-zhilian-content-studio) | 内容管理工作台 |

## 访问地址

| 服务 | 地址 |
|------|------|
| Web App | https://mianshi-zhilian-app.pages.dev |
| 内容 CDN | https://mianshi-zhilian-content.pages.dev |
| Worker API | https://mianshi-zhilian-api.nontracey.workers.dev |

## 版本历史

### v0.1.0 (2026-05-27)
- 学习中心、领域知识目录、知识点详情
- 文本/语音复述练习、AI 评估
- 模拟面试、今日复习、随机抽问
- 用户名密码登录、云端数据同步
- 主题设置、语言切换、检查更新
- Web/Android/macOS/Windows 多端支持
