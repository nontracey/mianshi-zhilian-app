import re

with open('lib/l10n/l10n.dart') as f:
    content = f.read()

# Pattern for key-value pairs: handles \' escaping in values
entry_pattern = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\]|\\.)*)'\s*,?$", re.MULTILINE)

def unescape_dart(v):
    v = v.replace("\\'", "'")
    v = v.replace("\\\\", "\\")
    return v

def escape_dart(v):
    v = v.replace("\\", "\\\\")
    v = v.replace("'", "\\'")
    return v

# Find the _en section start
en_marker = '  static const _en = {'
en_idx = content.find(en_marker)

# ========== Collect _zh entries from text BEFORE _en section ==========
zh_text = content[:en_idx] if en_idx >= 0 else content
all_zh = {}
zh_order = []

for m in entry_pattern.finditer(zh_text):
    key = m.group(1)
    raw = m.group(2)
    val = unescape_dart(raw)
    if key not in all_zh:
        all_zh[key] = val
        zh_order.append(key)

print(f'Unique _zh entries: {len(all_zh)}')

# ========== Collect _en entries from text AFTER _en section ==========
all_en = {}
en_order = []

if en_idx >= 0:
    en_text = content[en_idx:]
    for m in entry_pattern.finditer(en_text):
        key = m.group(1)
        raw = m.group(2)
        val = unescape_dart(raw)
        if key not in all_en:
            all_en[key] = val
            en_order.append(key)

print(f'Unique _en entries: {len(all_en)}')

# ========== Analyze overlap ==========
zh_keys = set(all_zh.keys())
en_keys = set(all_en.keys())
common = zh_keys & en_keys
zh_only = zh_keys - en_keys
en_only = en_keys - zh_keys
print(f'Keys in both: {len(common)}')
print(f'Only in _zh: {len(zh_only)}')
print(f'Only in _en: {len(en_only)}')

# ========== Build the clean file ==========

def write_entries(entries, order, exclude=None):
    if exclude is None:
        exclude = set()
    result = []
    for k in order:
        if k in exclude:
            continue
        if k in entries:
            v = escape_dart(entries[k])
            result.append(f"    '{k}': '{v}',")
    return '\n'.join(result)

template_keys = ['template_short_example', 'template_standard_example', 'template_deep_example']

lines = []
lines.append("import 'package:flutter/material.dart';")
lines.append('')
lines.append('class L10n {')
lines.append('')

# _zh section
lines.append('  static const _zh = {')
zh_exclude = set(template_keys)
zh_main = write_entries(all_zh, zh_order, exclude=zh_exclude)
if zh_main:
    lines.append(zh_main)
lines.append('')
for k in template_keys:
    if k in all_zh:
        v = escape_dart(all_zh[k])
        lines.append(f"    '{k}': '{v}',")
lines.append('  };')
lines.append('')

# _en section
lines.append('  static const _en = {')
en_exclude = set(template_keys)
en_main = write_entries(all_en, en_order, exclude=en_exclude)
if en_main:
    lines.append(en_main)
lines.append('')
for k in template_keys:
    if k in all_en:
        v = escape_dart(all_en[k])
        lines.append(f"    '{k}': '{v}',")
lines.append('  };')
lines.append('')

# Get method
lines.append('  static String get(String key, String language) {')
lines.append('    final map = language == "en" ? _en : _zh;')
lines.append('    return map[key] ?? key;')
lines.append('  }')
lines.append('')
lines.append('  static List<Locale> get supportedLocales => [')
lines.append("    const Locale('zh'),")
lines.append("    const Locale('en'),")
lines.append('  ];')
lines.append('}')
lines.append('')

output = '\n'.join(lines)

with open('lib/l10n/l10n.dart', 'w') as f:
    f.write(output)

print(f'\nFile rebuilt: {len(output.split(chr(10)))} lines')