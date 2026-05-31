#!/usr/bin/env python3
"""All-in-one: Replace Chinese, add imports, add class-level l10n getter, remove const."""
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

# ===== Part 1: Chinese string replacement =====
all_keys = set()
new_keys_to_add = {}

def get_existing_keys():
    with open(L10N_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    return set(re.findall(r"'([a-z_][a-z0-9_]*)':", content))

def chinese_to_key(text):
    clean = text.strip()
    if not clean or not re.search(r'[\u4e00-\u9fff]', clean):
        return None
    if '$' in clean:
        return None
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

def replace_chinese_in_line(line):
    if should_skip_line(line):
        return line, False
    
    line = re.sub(r'\bconst\s+(Text\s*\()', r'\1', line)
    
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
    
    new_line = re.sub(r"'([^'$]*[\u4e00-\u9fff][^'$]*)'", replacer_single, line)
    new_line = re.sub(r'"([^"$]*[\u4e00-\u9fff][^"$]*)"', replacer_double, new_line)
    
    return new_line, changed

def add_keys_to_l10n():
    if not new_keys_to_add:
        return
    with open(L10N_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    
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
    
    zh_entries = []
    en_entries = []
    for key, zh_text in sorted(new_keys_to_add.items()):
        escaped = zh_text.replace("\\", "\\\\").replace("'", "\\'")
        zh_entries.append(f"    '{key}': '{escaped}',")
        en_entries.append(f"    '{key}': '{escaped}',")
    
    zh_insert = '\n'.join(zh_entries) + '\n'
    content = content[:zh_end] + zh_insert + '  ' + content[zh_end:]
    
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

# ===== Part 2: Add class-level l10n getter and fix scoping =====

def find_class_type(lines):
    """Returns list of (start_line, end_line, is_state_class, class_name)."""
    classes = []
    depth = 0
    cls_start = -1
    cls_name = ''
    is_state = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        m = re.match(r'class\s+(\w+)', stripped)
        if m and depth == 0:
            cls_start = i
            cls_name = m.group(1)
            is_state = bool(re.match(r'class\s+\w+\s+extends\s+State<', stripped))
        
        for ch in stripped:
            if ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and cls_start >= 0:
                    classes.append((cls_start, i, is_state, cls_name))
                    cls_start = -1
    
    return classes

def add_l10n_getter(lines, cls_start, cls_end, class_name):
    """Add a class-level l10n getter after the class opening brace."""
    # Find the line with the class opening brace
    brace_line = cls_start
    for i in range(cls_start, min(cls_start + 3, cls_end)):
        if '{' in lines[i]:
            brace_line = i
            break
    
    # Check if l10n getter already exists
    for i in range(brace_line, min(brace_line + 5, cls_end)):
        if 'get l10n' in lines[i] or 'final l10n' in lines[i]:
            return False
    
    # Get indent (2 more than class indent)
    indent_match = re.match(r'^(\s*)', lines[cls_start])
    indent = (indent_match.group(1) if indent_match else '') + '  '
    
    getter = f'{indent}LocalizationProvider get l10n => context.watch<LocalizationProvider>();'
    lines.insert(brace_line + 1, getter)
    return True

def process_file(filepath):
    """Process a single file: replace Chinese, add imports, add l10n getter, remove const."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Step 1: Replace Chinese strings
    orig_lines = content.split('\n')
    new_lines = []
    chinese_changes = 0
    for line in orig_lines:
        new_line, changed = replace_chinese_in_line(line)
        if changed:
            chinese_changes += 1
        new_lines.append(new_line)
    lines = new_lines
    
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        if chinese_changes > 0:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
        return chinese_changes
    
    # Step 2: Add import
    is_widget = '/widgets/' in filepath
    if 'localization_provider.dart' not in '\n'.join(lines):
        import_line = "import '../providers/localization_provider.dart';" if is_widget else "import '../../providers/localization_provider.dart';"
        last_import = -1
        for i, line in enumerate(lines):
            if line.strip().startswith('import '):
                last_import = i
        if last_import >= 0:
            lines.insert(last_import + 1, import_line)
    
    # Step 3: Remove const from lines with l10n.get()
    for i in range(len(lines)):
        if 'l10n.get' in lines[i]:
            lines[i] = re.sub(r'\bconst\s+', '', lines[i])
    
    # Step 4: Find classes and add l10n getter
    classes = find_class_type(lines)
    
    getter_added = 0
    for (cls_start, cls_end, is_state, cls_name) in classes:
        if is_state:
            # State class: add class-level getter
            if add_l10n_getter(lines, cls_start, cls_end, cls_name):
                getter_added += 1
                # Adjust subsequent class ranges
                # (not needed since we process all at once and insert from top)
        else:
            # Non-State class: check if build method exists and uses l10n
            # Find build method
            for i in range(cls_start + 1, cls_end):
                if re.match(r'^\s+(?:@\w+\s+)?Widget\s+build\s*\(', lines[i]):
                    # Find opening brace
                    brace_line = i
                    for j in range(i, min(i + 5, cls_end)):
                        if '{' in lines[j]:
                            brace_line = j
                            break
                    
                    # Check if build contains l10n.get
                    has_l10n_in_build = False
                    d = 0
                    for j in range(brace_line, cls_end):
                        for ch in lines[j]:
                            if ch == '{': d += 1
                            elif ch == '}': d -= 1
                        if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                            has_l10n_in_build = True
                        if d == 0 and j > brace_line:
                            break
                    
                    if has_l10n_in_build:
                        # Check if l10n already declared
                        has_decl = False
                        for j in range(brace_line, min(brace_line + 5, cls_end)):
                            if 'final l10n' in lines[j] or 'get l10n' in lines[j]:
                                has_decl = True
                                break
                        if not has_decl:
                            indent_match = re.match(r'^(\s*)', lines[brace_line])
                            indent = (indent_match.group(1) if indent_match else '') + '  '
                            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
                            lines.insert(brace_line + 1, decl)
                            getter_added += 1
                    break
    
    # Step 5: For State classes with getter, we need to handle the case where
    # helper methods don't have `context` available (they're called with context as param).
    # The class-level getter uses `this.context` from State, so it works in all methods.
    # But we also need to handle non-class functions.
    
    # Find all l10n.get usages and check if they're inside a class with l10n getter
    # If not, they need their own declaration
    l10n_lines = set()
    for i, line in enumerate(lines):
        if 'l10n.get' in line and not line.strip().startswith('//'):
            l10n_lines.add(i)
    
    # For each l10n line, check if it's inside a class with a getter
    for ll in sorted(l10n_lines):
        in_class = False
        for (cls_start, cls_end, is_state, cls_name) in classes:
            if cls_start <= ll <= cls_end:
                in_class = True
                break
        if not in_class:
            # This is a top-level l10n.get usage - needs special handling
            # Find the enclosing function
            # For now, just report
            print(f"  ⚠️  Top-level l10n.get at {os.path.basename(filepath)}:{ll+1}")
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    
    return chinese_changes + getter_added

def main():
    global all_keys
    all_keys = get_existing_keys()
    total = 0
    
    for f in FILES:
        path = os.path.join(BASE, f)
        if not os.path.exists(path):
            print(f"❌ {f}")
            continue
        changes = process_file(path)
        total += changes
        if changes > 0:
            print(f"✅ {f}: {changes} changes")
        else:
            print(f"⏭️  {f}: no changes")
    
    add_keys_to_l10n()
    print(f"\nTotal: {total} changes")

if __name__ == '__main__':
    main()
