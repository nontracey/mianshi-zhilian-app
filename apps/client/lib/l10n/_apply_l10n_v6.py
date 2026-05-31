#!/usr/bin/env python3
"""v6: Safe replacement of Chinese UI strings using re.sub callbacks.
Only replaces pure Chinese text (no $variables). Skips matching logic, comments."""
import re, os, hashlib

BASE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib'
L10N_FILE = os.path.join(BASE, 'l10n/l10n.dart')

FILES = [
    'widgets/header_bar.dart',
    'widgets/navigation_rail_panel.dart',
    'pages/learning/catalog_page.dart',
    'pages/learning/topic_detail_page.dart',
    'pages/learning/dashboard_page.dart',
    'pages/practice/practice_page.dart',
    'pages/practice/recall_page.dart',
    'pages/practice/today_review_page.dart',
    'pages/practice/mock_interview_page.dart',
    'pages/practice/system_design_page.dart',
    'pages/practice/answer_versions_page.dart',
    'pages/prep/interview_prep_page.dart',
    'pages/mastery/mastery_page.dart',
    'pages/profile/profile_page.dart',
]

# Global key registry
all_keys = set()
new_keys_to_add = {}

def get_existing_keys():
    with open(L10N_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    return set(re.findall(r"'([a-z_][a-z0-9_]*)':", content))

def chinese_to_key(text):
    """Generate a stable l10n key from Chinese text."""
    clean = text.strip()
    if not clean or not re.search(r'[\u4e00-\u9fff]', clean):
        return None
    if '$' in clean:
        return None
    # Generate readable key
    key = clean
    key = re.sub(r'[，。！？、；：""''（）【】《》「」/\s]+', '_', key)
    key = re.sub(r'[^\w]', '', key)
    key = key.strip('_')
    if len(key) > 40 or not key:
        h = hashlib.md5(clean.encode()).hexdigest()[:8]
        key = f'text_{h}'
    return key

def should_skip_line(line):
    stripped = line.strip()
    if stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
        return True
    if 'l10n.get' in line:
        return True
    if stripped.startswith('import '):
        return True
    if re.search(r'\.contains\(|\.startsWith\(|\.endsWith\(', stripped):
        return True
    if 'debugPrint' in stripped:
        return True
    return False

def replace_chinese_string(match):
    """Callback for re.sub - replaces a Chinese string literal with l10n.get()."""
    quote = match.group(1)  # ' or "
    chinese_text = match.group(2)
    
    # Skip if too short
    if len(chinese_text) <= 1:
        return match.group(0)
    
    # Skip if contains $ (variable)
    if '$' in chinese_text:
        return match.group(0)
    
    # Skip if no Chinese characters
    if not re.search(r'[\u4e00-\u9fff]', chinese_text):
        return match.group(0)
    
    key = chinese_to_key(chinese_text)
    if not key:
        return match.group(0)
    
    # Register key
    if key not in all_keys:
        all_keys.add(key)
        new_keys_to_add[key] = chinese_text
    
    return f"l10n.get('{key}')"

def process_line(line):
    """Process a single line, replacing Chinese strings."""
    if should_skip_line(line):
        return line, False
    
    # Remove const before Text(...) containing Chinese
    line = re.sub(r'\bconst\s+(Text\s*\()', r'\1', line)
    
    # Replace Chinese string literals
    # Use separate patterns for single and double quoted strings
    # to avoid matching across quote boundaries
    changed = False
    
    def replacer_single(m):
        nonlocal changed
        text = m.group(1)
        if len(text) <= 1 or '$' in text or not re.search(r'[\u4e00-\u9fff]', text):
            return m.group(0)
        key = chinese_to_key(text)
        if not key:
            return m.group(0)
        if key not in all_keys:
            all_keys.add(key)
            new_keys_to_add[key] = text
        changed = True
        return f"l10n.get('{key}')"
    
    def replacer_double(m):
        nonlocal changed
        text = m.group(1)
        if len(text) <= 1 or '$' in text or not re.search(r'[\u4e00-\u9fff]', text):
            return m.group(0)
        key = chinese_to_key(text)
        if not key:
            return m.group(0)
        if key not in all_keys:
            all_keys.add(key)
            new_keys_to_add[key] = text
        changed = True
        return f"l10n.get('{key}')"
    
    # Single-quoted: content between ' that doesn't contain ' or $
    new_line = re.sub(r"'([^'$]*[\u4e00-\u9fff][^'$]*)'", replacer_single, line)
    # Double-quoted: content between " that doesn't contain " or $
    new_line = re.sub(r'"([^"$]*[\u4e00-\u9fff][^"$]*)"', replacer_double, new_line)
    
    return new_line, changed

def add_keys_to_l10n():
    """Add new keys to both _zh and _en maps."""
    if not new_keys_to_add:
        return
    
    with open(L10N_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find _zh map closing brace
    zh_start = content.find('static const _zh = {')
    brace_count = 0
    i = content.find('{', zh_start)
    while i < len(content):
        if content[i] == '{': brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0: break
        i += 1
    zh_end = i
    
    # Find _en map closing brace
    en_start = content.find('static const _en = {')
    brace_count = 0
    i = content.find('{', en_start)
    while i < len(content):
        if content[i] == '{': brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0: break
        i += 1
    en_end = i
    
    # Build entries
    zh_entries = []
    en_entries = []
    for key, zh_text in sorted(new_keys_to_add.items()):
        escaped = zh_text.replace("\\", "\\\\").replace("'", "\\'")
        zh_entries.append(f"    '{key}': '{escaped}',")
        en_entries.append(f"    '{key}': '{escaped}',")
    
    # Insert into _zh
    zh_insert = '\n'.join(zh_entries) + '\n'
    content = content[:zh_end] + zh_insert + '  ' + content[zh_end:]
    
    # Recalculate _en position
    shift = len(zh_insert) + 2
    en_start_new = en_start + shift
    brace_count = 0
    i = content.find('{', en_start_new)
    while i < len(content):
        if content[i] == '{': brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0: break
        i += 1
    en_end_new = i
    
    en_insert = '\n'.join(en_entries) + '\n'
    content = content[:en_end_new] + en_insert + '  ' + content[en_end_new:]
    
    with open(L10N_FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"  Added {len(new_keys_to_add)} new keys to l10n.dart")

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    changes = 0
    
    for line in lines:
        new_line, changed = process_line(line)
        if changed:
            changes += 1
        new_lines.append(new_line)
    
    if changes > 0:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
    
    return changes

def main():
    global all_keys
    all_keys = get_existing_keys()
    total_changes = 0
    
    for f in FILES:
        path = os.path.join(BASE, f)
        if not os.path.exists(path):
            print(f"❌ {f}")
            continue
        changes = process_file(path)
        total_changes += changes
        if changes > 0:
            print(f"✅ {f}: {changes} lines changed")
        else:
            print(f"⏭️  {f}: no changes")
    
    add_keys_to_l10n()
    print(f"\nTotal: {total_changes} lines changed")

if __name__ == '__main__':
    main()
