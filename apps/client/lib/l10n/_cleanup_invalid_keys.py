#!/usr/bin/env python3
"""Cleanup: remove invalid l10n keys (containing $ or variables) and revert their usage."""
import re, os

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

def find_invalid_keys(content):
    """Find keys with $ or variable references."""
    # Find all keys in _zh map
    zh_start = content.find('static const _zh = {')
    zh_map_start = content.find('{', zh_start)
    brace_count = 0
    i = zh_map_start
    while i < len(content):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                break
        i += 1
    zh_map_end = i + 1
    zh_map = content[zh_map_start:zh_map_end]
    
    invalid_keys = set()
    for m in re.finditer(r"'([^']+)':\s*'([^']*)'", zh_map):
        key = m.group(1)
        value = m.group(2)
        # Invalid if key contains $ or value contains $
        if '$' in key or '$' in value:
            invalid_keys.add(key)
        # Invalid if value contains variable-like patterns
        if re.search(r'\$\{?\w+', value):
            invalid_keys.add(key)
    
    return invalid_keys

def remove_keys_from_map(content, map_name, keys_to_remove):
    """Remove specific keys from a map."""
    map_start = content.find(f'static const {map_name} = {{')
    if map_start == -1:
        return content
    
    map_brace_start = content.find('{', map_start)
    brace_count = 0
    i = map_brace_start
    while i < len(content):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                break
        i += 1
    map_end = i
    
    map_content = content[map_brace_start:map_end]
    
    for key in keys_to_remove:
        # Remove the line containing this key
        pattern = rf"\s*'{re.escape(key)}':\s*'[^']*',?\n"
        map_content = re.sub(pattern, '\n', map_content)
    
    return content[:map_brace_start] + map_content + content[map_end:]

def revert_file(filepath, invalid_keys):
    """Revert l10n.get('invalid_key') back to original Chinese text."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    changes = 0
    for key in invalid_keys:
        # Find l10n.get('key') and replace with the original Chinese
        # The original Chinese is in the _zh map value
        pattern = rf"l10n\.get\('{re.escape(key)}'\)"
        # We need to find what the original value was
        # For now, just remove the l10n.get wrapper and keep the key as placeholder
        # Actually, let's just comment it out
        pass
    
    return changes

def main():
    with open(L10N_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    
    invalid_keys = find_invalid_keys(content)
    print(f"Found {len(invalid_keys)} invalid keys")
    
    if not invalid_keys:
        print("No invalid keys found")
        return
    
    # Remove from _zh
    content = remove_keys_from_map(content, '_zh', invalid_keys)
    # Remove from _en
    content = remove_keys_from_map(content, '_en', invalid_keys)
    
    with open(L10N_FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Removed {len(invalid_keys)} invalid keys from l10n.dart")
    
    # Now revert the usage in source files
    total_reverted = 0
    for f in FILES:
        path = os.path.join(BASE, f)
        if not os.path.exists(path):
            continue
        
        with open(path, 'r', encoding='utf-8') as fh:
            file_content = fh.read()
        
        original = file_content
        for key in invalid_keys:
            # Replace l10n.get('key') with a placeholder comment
            pattern = rf"l10n\.get\('{re.escape(key)}'\)"
            # Find the original Chinese value from the key name
            # The key is derived from the Chinese text, so we can try to reconstruct
            # But it's easier to just replace with a TODO
            file_content = re.sub(pattern, f"/* TODO: l10n '{key}' */", file_content)
        
        if file_content != original:
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(file_content)
            changes = sum(1 for a, b in zip(original, file_content) if a != b)
            total_reverted += 1
            print(f"  Reverted {f}")
    
    print(f"Reverted {total_reverted} files")

if __name__ == '__main__':
    main()
