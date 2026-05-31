import re

with open('lib/l10n/l10n.dart') as f:
    content = f.read()

# Find section boundaries
new_zh_start = content.find('    // UI i18n keys (auto-generated English identifiers)')
zh_close = content.find('  };\n\n  static const _en = {')
new_zh_end = content.rfind('    };', new_zh_start, zh_close) + 6  # include '    };'

print(f'new_zh_start={new_zh_start}, zh_close={zh_close}, new_zh_end={new_zh_end}')

# Extract original zh section
original_zh = content[:new_zh_start]
original_keys = set()
for line in original_zh.split('\n'):
    m = re.match(r"\s+'([^']+)':\s+'[^']*',", line)
    if m:
        original_keys.add(m.group(1))

print(f'Original keys count: {len(original_keys)}')

# Extract new zh section lines
new_zh_part = content[new_zh_start:new_zh_end]
new_lines = new_zh_part.split('\n')
print(f'Lines in new section: {len(new_lines)}')

# Filter out duplicate keys
filtered_lines = []
removed_count = 0
total_new = 0
for line in new_lines:
    m = re.match(r"\s+'([^']+)':\s+'[^']*',", line)
    if m:
        total_new += 1
        key = m.group(1)
        if key in original_keys:
            removed_count += 1
            continue  # skip duplicate
    filtered_lines.append(line)

filtered_new = '\n'.join(filtered_lines)

# Rebuild content
new_content = content[:new_zh_start] + filtered_new + content[new_zh_end:]

with open('lib/l10n/l10n.dart', 'w') as f:
    f.write(new_content)

print(f'Total new entries: {total_new}')
print(f'Removed duplicates: {removed_count}')
print(f'Kept: {total_new - removed_count}')
