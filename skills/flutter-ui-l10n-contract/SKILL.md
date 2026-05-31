---
name: flutter-ui-l10n-contract
description: Enforce this app's Flutter UI localization contract whenever UI-visible text is added, changed, audited, or refactored.
source: project
---

# Flutter UI l10n Contract

## When to use

Use this skill for any change that can affect UI-visible text in `apps/client/lib`, including pages, widgets, dialogs, snack bars, tooltips, labels, buttons, empty states, validation messages, settings options, and enum/model labels shown by the UI.

## Contract

- Default language is Chinese (`zh`).
- UI code must call `l10n.get('english_snake_case_key')` or `l10n.getp('english_snake_case_key', params)`.
- Call sites must not change when more languages are added.
- Keys must be stable English `snake_case`, start with a letter, and contain only lowercase letters, digits, and underscores.
- Keys must not contain Chinese, pinyin, Unicode/hex Chinese, punctuation, spaces, `{param}` placeholders, or display text fragments.
- Keys must not repeat within a locale map.
- Every supported locale map in `lib/l10n/l10n.dart` must expose the same key set.
- Parameters belong in values, not keys. Example: use key `items_count` with value `'{count} 项'`, never key `'{count}_items'`.
- Placeholder names must match across all languages.
- Dynamic user/content data should remain data; only UI chrome and app-authored display text is localized.
- Common hardcoded Chinese UI literals are rejected by `lib/l10n/check_l10n_keys.py`, including `Text('中文')`, `SnackBar(content: Text('中文'))`, form `labelText`/`hintText`, Chinese `labelKey`/`titleKey`/`nameKey` config values, and label-like getters returning Chinese text.
- The checker cannot reliably classify every English literal; treat English UI chrome such as buttons, field labels, status text, and settings names as localizable unless it is a technical constant or brand name.

## Implementation Pattern

1. Get localization in widgets with:

```dart
final l10n = context.watch<LocalizationProvider>();
```

2. Replace UI literals with l10n calls:

```dart
Text(l10n.get('learning_mode'))
Text(l10n.getp('score_label', {'score': '$score', 'label': label}))
```

3. Add the key to both `_zh` and `_en` in `apps/client/lib/l10n/l10n.dart`.

4. For enum/model labels, return a `labelKey` or other stable key from the model layer and translate in the UI layer.

```dart
String get labelKey => 'content_published';
// UI: Text(l10n.get(item.labelKey))
```

## Validation

Run this after any UI text change:

```bash
cd apps/client
python3 lib/l10n/check_l10n_keys.py
```

The repository pre-commit check also runs this script before Flutter analysis, tests, and web build.

The script checks key shape, duplicate keys, locale-map synchronization, missing consumer keys, placeholder consistency, and common hardcoded Chinese UI text. If it fails on a literal that is truly content data or an internal prompt marker, keep the data out of UI chrome rather than weakening the l10n contract.

## Avoid

- `Text('中文')` or `Text('English')` for UI chrome.
- `l10n.get('学习模式')`.
- `l10n.getp('{count}_items', {'count': count})`.
- `l10n.getp(l10n.get('some_key'), params)`.
- Adding a key to only one locale map.
