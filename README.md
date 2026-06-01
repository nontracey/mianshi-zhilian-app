# 面试智练 App

面试智练是一款 AI 主动回忆学习工作台，通过"知识学习 → 主动复述 → AI 评估纠错 → 掌握度更新"帮助用户系统备战技术面试。

## 功能特性

### 学习工作台
- **三栏布局**：左侧复习队列、中间学习路线、右侧掌握度概览
- **今日复习队列**：基于遗忘曲线，展示到期、逾期、薄弱知识点
- **薄弱知识点 TOP 5**：快速定位需要加强的内容
- **掌握度趋势**：近 7 天掌握度变化图表

### 知识学习
- **领域知识目录**：多维度筛选（难度、高频、代码题、LeetCode）
- **知识详情**：Tab 切换布局（知识查阅 / 复述练习）
- **前置知识**：显示具体名称，支持点击跳转
- **学习路线**：按阶段分组，支持展开查看详情

### 练习模式
- **复述练习**：文本/语音/图片/代码多模态输入，AI 评估纠错
- **追问训练**：模拟面试官追问，渐进提示
- **弱点训练包**：按错因分类（概念缺失/混淆/表达不清等）
- **高频冲刺**：针对高频面试题强化训练
- **项目深挖**：STAR 模板练习，本地维护项目信息
- **系统设计**：需求澄清、容量估算、架构草图（从内容仓库动态加载）

### 模拟面试
- **场景选择**：基础知识、项目深挖、系统设计、代码题、行为面试
- **面试房间**：计时、连续答题、追问
- **面试报告**：总分、维度评分、下一轮训练包

### 掌握度系统
- **掌握度看板**：领域切换、熟练度排序、诊断指标
- **今日复习**：到期/逾期/薄弱回流分组
- **就绪度评分**：综合评估面试准备程度

### 面试准备
- **准备目标**：目标岗位、面试日期、技术栈
- **JD 解析**：粘贴 JD 自动提取关键词，匹配知识点并按掌握度排序
- **训练计划**：根据面试日期自动生成冲刺节奏
- **回答版本库**：初稿 → AI 修改 → 面试版，支持版本对比
- **项目深挖库**：本地维护项目背景、技术决策

### AI 配置
- **多配置支持**：支持多个 AI 服务配置
- **流式输出**：打字机模式实时显示 AI 分析
- **模型选择**：导航栏快速切换
- **未配置降级**：本地练习模式
- **Whisper STT**：支持 Whisper 兼容语音识别（自定义端点）

### 个性化设置
- **主题系统**：典雅白、气质黑、午夜蓝、活力橙 4 种内置主题
- **主题自定义**：主色/强调色自定义，实时预览
- **侧边栏**：支持收缩/展开
- **语言设置**：中英文切换
- **数据管理**：导出/清除本地数据
- **WebDAV 同步**：备份到/恢复自 WebDAV 服务器
- **OTA 更新**：应用内检查更新 + SHA256 校验

### 用户系统
- **注册登录**：确认密码校验、防注入处理
- **修改密码**：输入原密码修改
- **工单系统**：密码重置申请、反馈建议
- **数据同步**：本地优先 + 云端同步

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
│   │   │   ├── webdav_sync_service.dart
│   │   │   ├── whisper_stt_service.dart
│   │   │   └── update_service.dart
│   │   ├── widgets/            # 通用组件
│   │   ├── utils/              # 工具类
│   │   └── theme/              # 主题配置
│   └── pubspec.yaml
├── workers/api/                 # Cloudflare Worker API
│   ├── src/index.ts            # API 路由和处理
│   └── wrangler.toml           # Worker 配置
├── scripts/                     # 构建脚本
├── skills/                      # 项目级 AI 技能（skills），供 CLI/agent 共享使用
│   └── doc-code-audit/          # 文档 vs 代码一致性审计
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

## 提交前检查

**重要：提交代码前必须运行本地检查脚本，避免 CI 报错。**

```bash
# 在项目根目录运行
./scripts/pre-commit-check.sh
```

脚本会依次执行：
1. `flutter pub get` - 获取依赖
2. `flutter analyze --no-fatal-infos` - 静态分析
3. `flutter test` - 运行测试
4. `flutter build web --release` - 构建 Web

全部通过后方可提交推送。

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

## 支持项目

如果这个项目对你有帮助，欢迎[请作者喝杯咖啡 ☕](docs/sponsor.md)。
