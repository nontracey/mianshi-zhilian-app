---
name: commit-push
description: 提交推送规范——commit message 必须中文、必须遵循 .gitmessage 格式，适用于所有 git push 操作
source: project
keywords: [推送, 提交, commit, push, 提交说明, 提交信息, gitmessage]
---

# 提交推送规范（Commit & Push）

## 触发关键词

> `推送` / `提交` / `push` / `commit` / `提交代码` / `提交变更`

## 核心规则

所有 git 提交推送操作必须满足以下两条硬性要求，**不允许例外**：

### 规则 1：提交说明必须使用中文

- 描述变更内容时必须用中文撰写
- 不得使用英文（除非是专有名词、API 名称、标识符等不可翻译部分）
- 聚焦"为什么做"和"做了什么"，而非实现细节

### 规则 2：必须遵循 `.gitmessage` 格式

格式模板（参见项目根目录 `.gitmessage`）：

```
<type>: <中文描述>
```

**类型（必填）：**

| 类型 | 含义 | Release notes 分组 |
|------|------|-------------------|
| `feat` | 新功能 | ✨ 新功能 |
| `fix` | 问题修复 | 🐛 问题修复 |
| `docs` | 文档更新 | 📝 文档更新 |
| `refactor` | 重构 | 🔧 其他改动 |
| `perf` | 性能优化 | 🔧 其他改动 |
| `test` | 测试相关 | 🔧 其他改动 |
| `chore` | 构建/工具/配置 | 🔧 其他改动 |
| `ci` | CI/CD 变更 | （排除，不出现在 release notes） |
| `revert` | 回退操作 | （排除） |

**描述示例：**

```
feat: 掌握度看板支持按月筛选
fix: 登录页键盘弹起后按钮被遮挡
refactor: AuthProvider 改用 ProxyProvider 同步语言设置
chore: 构建号 112→113
ci: 添加 pub-cache 缓存加速依赖安装
```

**多行描述：** 一个点一行写完，多个点可以多行。

## 前置检查

在提交前，**必须**在项目根目录运行提交前检查脚本，确保代码通过所有质量门禁：

```bash
cd /Users/yingjunchi/code/mianshi-zhilian-app
./scripts/pre-commit-check.sh
```

该脚本依次执行：`flutter pub get` → 生成版本文件 → l10n key 校验 → `flutter analyze` → `flutter test` → `flutter build web --release`。任何一步失败则中止，修复后再继续。

## 操作步骤

### 1. 暂存变更

```bash
git add -A
# 或用 git add <具体文件> 选择性暂存
```

### 2. 撰写提交说明

```bash
# 方式 A：使用 gitmessage 模板
git commit -t .gitmessage
# 这会打开编辑器，填入模板后再编写

# 方式 B：直接写（确保符合格式）
git commit -m "feat: 掌握度看板支持按月筛选"
```

> 推荐方式 A（用模板），避免遗漏格式。

### 3. 推送到远端

```bash
# 首次推送当前分支
git push origin HEAD

# 或推指定分支
git push origin <branch-name>
```

### 4. 提交前自我检查清单

- [ ] commit message 是中文
- [ ] commit message 以 `<type>:` 开头（`feat`/`fix`/`chore`/`refactor`/`docs`/`perf`/`test`/`ci`/`revert`）
- [ ] type 和冒号之间没有空格
- [ ] 冒号后有一个空格再写描述
- [ ] 描述聚焦"为什么做"和"做了什么"，而非逐行实现细节

## 与「发布构建」「发布新版本」的关系

`commit-push` 是通用技能，适用于**任意**代码提交推送操作。`release-build` 和 `release-new-version` 是它的特化版本——在遵循本 skill 所有规则的基础上，额外处理构建号递增和版本 tag 操作。

发布构建/发布新版本时，也会调用本 skill 的 commit message 规则，无需重复约束。