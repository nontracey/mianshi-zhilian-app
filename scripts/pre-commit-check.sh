#!/bin/bash
# 本地 CI 检查脚本 - 提交前运行此脚本检查代码质量
# 用法: ./scripts/pre-commit-check.sh

set -e

echo "🔍 开始本地 CI 检查..."
echo ""

cd "$(dirname "$0")/../apps/client"

# 1. 获取依赖
echo "📦 Step 1/4: 获取依赖..."
flutter pub get
echo "✅ 依赖获取完成"
echo ""

# 2. 静态分析
echo "🔎 Step 2/4: 运行静态分析..."
if flutter analyze --no-fatal-infos; then
  echo "✅ 静态分析通过"
else
  echo "❌ 静态分析失败，请修复上面的问题"
  exit 1
fi
echo ""

# 3. 运行测试
echo "🧪 Step 3/4: 运行测试..."
if flutter test; then
  echo "✅ 测试通过"
else
  echo "❌ 测试失败，请修复上面的问题"
  exit 1
fi
echo ""

# 4. 构建 Web
echo "🏗️ Step 4/4: 构建 Web..."
if flutter build web --release; then
  echo "✅ Web 构建成功"
else
  echo "❌ Web 构建失败，请修复上面的问题"
  exit 1
fi
echo ""

echo "🎉 所有检查通过！可以安全提交了。"
