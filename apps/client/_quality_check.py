import re

with open('/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib/l10n/l10n.dart') as f:
    content = f.read()

pat = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\\\]|\\.)*)'\s*,?$", re.MULTILINE)

def has_cjk(s):
    for c in s:
        if ord(c) >= 0x4E00 and ord(c) <= 0x9FFF:
            return True
    return False

zh_start = content.find('static const _zh = {')
zh_end = content.find('static const _en = {')
zh_section = content[zh_start:zh_end]
en_section = content[zh_end:]

print('=== _zh entries with English values (shouldn\'t happen) ===')
for m in pat.finditer(zh_section):
    k = m.group(1)
    v = m.group(2)
    if not has_cjk(v) and has_cjk(k):
        print(f'  Chinese key with non-CJK value: "{k}" = "{v[:60]}"')

print()
print('=== _en entries with auto-generated placeholders ===')
auto_count = 0
for m in pat.finditer(en_section):
    k = m.group(1)
    v = m.group(2)
    expected = ' '.join(w.capitalize() for w in k.replace('_', ' ').split())
    if v == expected:
        auto_count += 1
        if auto_count <= 5:
            print(f'  Auto-generated: key="{k}" value="{v}"')
print(f'Total auto-generated: {auto_count}')

print()
print('=== Specific check: text_ea189e1f ===')
for m in pat.finditer(zh_section):
    if m.group(1) == 'text_ea189e1f':
        print(f'  _zh: {m.group(1)} = {m.group(2)}')
for m in pat.finditer(en_section):
    if m.group(1) == 'text_ea189e1f':
        print(f'  _en: {m.group(1)} = {m.group(2)}')
        break
else:
    print('  _en: NOT FOUND')
