#!/usr/bin/env python3
"""Remove duplicate keys from l10n.dart, keeping the LAST occurrence."""
import re

FILE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib/l10n/l10n.dart'

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

def dedup_map(map_text):
    """Remove duplicate keys, keeping last occurrence."""
    # Find all key-value pairs
    pattern = r"('[^']+':\s*'[^']*(?:\\.[^']*)*',?\s*)"
    # Better approach: split by lines and track keys
    lines = map_text.split('\n')
    key_lines = {}  # key -> (line_index, line_text)
    result_lines = []
    
    for i, line in enumerate(lines):
        # Check if this line has a key-value pair
        m = re.match(r"\s*'([^']+)':\s*'", line)
        if m:
            key = m.group(1)
            if key in key_lines:
                # Remove the previous occurrence
                old_idx = key_lines[key]
                result_lines[old_idx] = None  # Mark for removal
            key_lines[key] = len(result_lines)
        result_lines.append(line)
    
    # Filter out removed lines
    return '\n'.join(line for line in result_lines if line is not None)

# Process _zh map
zh_start = content.find('static const _zh = {')
if zh_start == -1:
    print("ERROR: Can't find _zh map")
    exit(1)

zh_map_start = content.find('{', zh_start)
# Find matching closing brace
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
zh_deduped = dedup_map(zh_map)

# Process _en map
en_start = content.find('static const _en = {')
en_map_start = content.find('{', en_start)
brace_count = 0
i = en_map_start
while i < len(content):
    if content[i] == '{':
        brace_count += 1
    elif content[i] == '}':
        brace_count -= 1
        if brace_count == 0:
            break
    i += 1
en_map_end = i + 1

en_map = content[en_map_start:en_map_end]
en_deduped = dedup_map(en_map)

# Rebuild file
new_content = content[:zh_map_start] + zh_deduped + content[zh_map_end:en_map_start] + en_deduped + content[en_map_end:]

# Count changes
zh_orig = len(re.findall(r"'[a-z_]+':", zh_map))
zh_new = len(re.findall(r"'[a-z_]+':", zh_deduped))
en_orig = len(re.findall(r"'[a-z_]+':", en_map))
en_new = len(re.findall(r"'[a-z_]+':", en_deduped))

print(f"_zh: {zh_orig} -> {zh_new} (removed {zh_orig - zh_new} duplicates)")
print(f"_en: {en_orig} -> {en_new} (removed {en_orig - en_new} duplicates)")

with open(FILE, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("✅ Done!")
