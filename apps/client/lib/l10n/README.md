# l10n 国际化系统

## 目录结构

- `l10n.dart` — 国际化字典，包含 `_zh`（中文）和 `_en`（英文）两个 map
- `_extract_chinese_keys.py` — CI 检查脚本，检测是否有中文 key 残留
- `key_mapping.json` — 历史迁移映射（中文 key → 英文 key），仅作追溯参考

## Key 命名规范

**所有 l10n key 必须使用英文 snake_case 标识符，禁止使用中文。**

```dart
// ✅ 正确
'learning_mode': '学习模式',

// ❌ 错误（key 是中文）
'学习模式': '学习模式',
```

### 原因

- **Key 是稳定标识符**：key 一经定义不应更改，value（翻译文本）可以随时优化
- **中英文分离**：key 使用英文确保代码可读性不受语言限制
- **工具链兼容**：英文 key 可被自动化工具正确解析

### 命名风格

- 全小写 snake_case
- 短横线分隔：`topic_count`、`interviewer_focus`
- 参数化 key 用 `_format` 后缀（可选）：`interviewer_focus_format`
- 避免拼音或 Unicode 编码形式的 key

## 检查脚本

```bash
python3 lib/l10n/_extract_chinese_keys.py
```

该脚本遍历所有 `.dart` 文件，扫描 `l10n.get('...')` 和 `l10n.getp('...')` 调用，
若 key 中包含中文字符则报错退出（exit code 1）。

## 添加新 key

1. 在 `_zh` 和 `_en` 两个 map 中分别添加条目
2. key 使用英文 snake_case
3. `_zh` 的 value 写中文，`_en` 的 value 写英文
4. 调用时使用 `l10n.get('your_key')` 或 `l10n.getp('your_key', {...})`
