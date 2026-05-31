import re

# Read original (from git) and current (from rebuild) files
with open('/tmp/l10n_orig.dart') as f:
    orig = f.read()

with open('lib/l10n/l10n.dart') as f:
    current = f.read()

# Pattern for key-value pairs
pat = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\\\]|\\.)*)'\s*,?$", re.MULTILINE)

def has_cjk(s):
    for c in s:
        if ord(c) >= 0x4E00 and ord(c) <= 0x9FFF:
            return True
    return False

def unescape(v):
    v = v.replace("\\'", "'")
    v = v.replace("\\\\", "\\")
    return v

def escape(v):
    v = v.replace("\\", "\\\\")
    v = v.replace("'", "\\'")
    return v

# Collect original entries (from git)
orig_zh = {}
orig_en = {}
curr_section = None
for line in orig.split('\n'):
    if 'static const _zh = {' in line:
        curr_section = 'zh'
    elif 'static const _en = {' in line:
        curr_section = 'en'
    elif curr_section:
        m = pat.match(line)
        if m:
            k, v = m.group(1), unescape(m.group(2))
            if curr_section == 'zh':
                orig_zh[k] = v
            else:
                orig_en[k] = v

print(f'Original _zh: {len(orig_zh)}, _en: {len(orig_en)}')

# Template keys that need special handling
template_keys = ['template_short_example', 'template_standard_example', 'template_deep_example']

# Collect entries from current file
zh_start = current.find('static const _zh = {')
zh_end = current.find('static const _en = {')
zh_text = current[zh_start:zh_end]
en_text = current[zh_end:]

# zh entries: collect ones WITH Chinese values (skip English-valued noise, skip templates)
new_zh = {}
for m in pat.finditer(zh_text):
    k, v = m.group(1), unescape(m.group(2))
    if k not in orig_zh and k not in template_keys and has_cjk(v):
        new_zh[k] = v

print(f'New _zh (Chinese-valued, English keys): {len(new_zh)}')

# en entries: all non-original from current
new_en = {}
for m in pat.finditer(en_text):
    k, v = m.group(1), unescape(m.group(2))
    if k not in orig_en:
        new_en[k] = v

print(f'New _en: {len(new_en)}')

# Template examples (they have multi-line values, extract manually)
zh_template = {}
en_template = {}

for m in pat.finditer(zh_text):
    k, v = m.group(1), unescape(m.group(2))
    if k in template_keys:
        zh_template[k] = v

for m in pat.finditer(en_text):
    k, v = m.group(1), unescape(m.group(2))
    if k in template_keys:
        en_template[k] = v

print(f'Template _zh: {len(zh_template)}, _en: {len(en_template)}')

# Classify new_en entries
# English keys: only keep if value is English (not Chinese)
# Chinese keys: backward compat, keep regardless
chinese_key_en = {}
english_key_en = {}
for k, v in new_en.items():
    if k in template_keys:
        continue  # handled separately
    if has_cjk(k):
        chinese_key_en[k] = v
    else:
        if not has_cjk(v):  # English key should have English value in _en
            english_key_en[k] = v
        else:
            print(f'  Skipping _en entry (English key with Chinese value): {k} = {v[:50]}')

print(f'New _en: Chinese keys={len(chinese_key_en)}, English keys={len(english_key_en)}')

# ========== Find entries in _zh that have NO _en match ==========
all_zh_keys = set(orig_zh.keys()) | set(new_zh.keys()) | set(zh_template.keys())
all_en_keys = set(orig_en.keys()) | set(english_key_en.keys()) | set(chinese_key_en.keys()) | set(en_template.keys())
zh_wo_en = all_zh_keys - all_en_keys
print(f'Keys in _zh but missing from _en: {len(zh_wo_en)}')

# Add any missing _zh keys to _en with placeholder values BEFORE building
for missing_key in zh_wo_en:
    eng_val = ' '.join(w.capitalize() for w in missing_key.replace('_', ' ').split())
    english_key_en[missing_key] = eng_val
    print(f'  Added missing _en entry: {missing_key} = {eng_val}')

# Recompute with fixes
all_en_keys = set(orig_en.keys()) | set(english_key_en.keys()) | set(chinese_key_en.keys()) | set(en_template.keys())
zh_wo_en_after = all_zh_keys - all_en_keys
if zh_wo_en_after:
    print(f'WARNING: Still missing _en entries for: {zh_wo_en_after}')
else:
    print('OK: All _zh entries have corresponding _en entries')

# ========== Build final file ==========

def write_section(entries, order, exclude=None, section_comment=None):
    if exclude is None:
        exclude = set()
    result = []
    if section_comment:
        result.append(f'    // {section_comment}')
    for k in order:
        if k in exclude:
            continue
        if k in entries:
            v = escape(entries[k])
            result.append(f"    '{k}': '{v}',")
    return '\n'.join(result)

# Rebuild from scratch for cleanliness
build = []
build.append("import 'package:flutter/material.dart';")
build.append('')
build.append('class L10n {')
build.append('')

# _zh section
build.append('  static const _zh = {')

# Original zh entries (maintain original order)
orig_order = list(orig_zh.keys())
# Separate original entries into sections
zh_common = {}
zh_template_from_orig = {}
for k in orig_order:
    if k in template_keys:
        zh_template_from_orig[k] = orig_zh[k]
    else:
        zh_common[k] = orig_zh[k]

zh_common_order = [k for k in orig_order if k not in template_keys]
zh_template_order = [k for k in template_keys if k in zh_template_from_orig]

build.append('    // Original entries')
for k in zh_common_order:
    v = escape(zh_common[k])
    build.append(f"    '{k}': '{v}',")

# New zh entries (English key -> Chinese value)
if new_zh:
    build.append('')
    build.append('    // UI i18n keys (auto-generated English identifiers)')
    new_keys_sorted = sorted(new_zh.keys())
    for k in new_keys_sorted:
        v = escape(new_zh[k])
        build.append(f"    '{k}': '{v}',")

# Template examples from current (use current version)
if zh_template:
    build.append('')
    build.append('    // Answer template examples')
    for k in template_keys:
        if k in zh_template:
            v = escape(zh_template[k])
            build.append(f"    '{k}': '{v}',")

build.append('  };')
build.append('')

# _en section
build.append('  static const _en = {')

# Original en entries
en_orig_common = {}
en_orig_template = {}
for k in orig_en:
    if k in template_keys:
        en_orig_template[k] = orig_en[k]
    else:
        en_orig_common[k] = orig_en[k]

build.append('    // Original entries')
for k in orig_en:
    if k not in template_keys:
        v = escape(orig_en[k])
        build.append(f"    '{k}': '{v}',")

# English key new en entries
if english_key_en:
    build.append('')
    build.append('    // UI i18n keys (auto-generated English identifiers)')
    for k in sorted(english_key_en.keys()):
        v = escape(english_key_en[k])
        build.append(f"    '{k}': '{v}',")

# Backward compat: Chinese keys that have English translations
if chinese_key_en:
    build.append('')
    build.append('    // Backward compatibility: original Chinese keys -> English translations')
    for k in chinese_key_en:
        v = escape(chinese_key_en[k])
        build.append(f"    '{k}': '{v}',")

# Template examples
if en_template:
    build.append('')
    build.append('    // Answer template examples')
    for k in template_keys:
        if k in en_template:
            v = escape(en_template[k])
            build.append(f"    '{k}': '{v}',")

build.append('  };')
build.append('')

# Get method
build.append('  static String get(String key, String language) {')
build.append('    final map = language == "en" ? _en : _zh;')
build.append('    return map[key] ?? key;')
build.append('  }')
build.append('')
build.append('  static List<Locale> get supportedLocales => [')
build.append("    const Locale('zh'),")
build.append("    const Locale('en'),")
build.append('  ];')
build.append('}')
build.append('')

output = '\n'.join(build)

with open('lib/l10n/l10n.dart', 'w') as f:
    f.write(output)

print(f'\nFinal file: {len(output.split(chr(10)))} lines')
print(f'Final _zh entries: {len(orig_zh) + len(new_zh) + len(zh_template)}')
print(f'Final _en entries: {len(orig_en) + len(english_key_en) + len(chinese_key_en) + len(en_template)}')
print('Done.')