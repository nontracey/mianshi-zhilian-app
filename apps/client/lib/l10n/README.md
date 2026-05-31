# l10n 国际化系统

## 目录结构

- `l10n.dart` — 国际化字典，包含 `_zh`（中文）和 `_en`（英文）两个 map
- `check_l10n_keys.py` — CI 检查脚本，检测 key 规范、重复 key、语言字典同步、调用缺失、参数占位符一致性和常见 UI 硬编码中文
- `key_mapping.json` — 历史迁移映射（中文 key → 英文 key），仅作追溯参考

## 运行时规则

- 默认语言是中文：`L10n.defaultLanguage == 'zh'`
- UI 调用只使用 `l10n.get('english_key')` 或 `l10n.getp('english_key', {...})`
- UI 可见文案（按钮、标题、设置项、空状态、SnackBar、表单 label/hint、enum/model 标签）必须走 l10n；不要把中文或英文展示文本直接写在 UI 代码里
- 调用层不关心具体语言数量；未来扩展新语言只需要在 `L10n._localizedValues` 中注册新的语言 map，并补齐同一组 key
- 找不到当前语言的翻译时会 fallback 到中文，再 fallback 到英文，最后才显示 key，便于定位缺失文案

## Key 命名规范

**所有 l10n key 必须使用英文 snake_case 标识符，禁止使用中文、拼音、Unicode/hex 中文编码、参数占位符或任意非英文标识形式。**

```dart
// ✅ 正确
'learning_mode': '学习模式',
'items_count': '{count} 项',

// ❌ 错误（key 是中文）
'学习模式': '学习模式',

// ❌ 错误（key 不是稳定英文标识符）
'{count}_items': '{count} 项',
'30_min': '30分钟',
```

### 原因

- **Key 是稳定标识符**：key 一经定义不应更改，value（翻译文本）可以随时优化
- **中英文分离**：key 使用英文确保代码可读性不受语言限制
- **工具链兼容**：英文 key 可被自动化工具正确解析

### 命名风格

- 全小写 snake_case
- 下划线分隔：`topic_count`、`interviewer_focus`
- 必须以英文字母开头，后续可包含数字：`time_30_min`
- 参数写在 value 中，不写在 key 中：`items_count` → `'{count} 项'`
- 避免拼音或 Unicode 编码形式的 key
- 同一个 map 内 key 不能重复；所有支持语言必须拥有完全相同的 key 集合
- 各语言 value 中的 `{param}` 占位符名称必须一致

## 检查脚本

```bash
python3 lib/l10n/check_l10n_keys.py
```

该脚本会报错退出（exit code 1）：

- key 不是英文 snake_case
- key 包含中文或 hex/Unicode 编码中文
- map 内有重复 key
- `_zh` / `_en` 等语言 map 的 key 集合不同
- 调用处引用未定义 key
- `getp()` 参数占位符在各语言之间不一致
- 常见 UI 展示入口硬编码中文，例如 `Text('中文')`、`SnackBar(content: Text('中文'))`、`labelText: '中文'`、`hintText: '中文'`
- `titleKey`、`descKey`、`nameKey`、`labelKey` 等配置字段使用中文文本，而不是英文 key
- label/title/name/description/frequency 类 getter 直接返回中文展示文本

允许的例外：

- 用户输入、内容数据、题目正文、知识库原文等业务数据
- 技术常量和示例值，例如 URL、模型名、`API Key`、`LeetCode`
- AI prompt 或内部上下文标记；如果这些文字会直接显示给用户，也必须迁移到 l10n

本地提交前脚本 `scripts/pre-commit-check.sh` 已集成该检查。

## 添加新 key

1. 在 `_zh` 和 `_en` 两个 map 中分别添加条目
2. key 使用英文 snake_case
3. `_zh` 的 value 写中文，`_en` 的 value 写英文
4. 调用时使用 `l10n.get('your_key')` 或 `l10n.getp('your_key', {...})`
5. 运行 `python3 lib/l10n/check_l10n_keys.py`

## 扩展新语言

1. 在 `l10n.dart` 中新增完整语言 map，例如 `_ja`
2. 在 `_localizedValues` 注册语言代码：`'ja': _ja`
3. 确保新 map 和 `_zh` key 完全一致
4. 运行 `python3 lib/l10n/check_l10n_keys.py`
