import re

with open('lib/l10n/l10n.dart') as f:
    content = f.read()

zh_start = content.find('static const _zh = {')
zh_end = content.find('static const _en = {')
zh_section = content[zh_start:zh_end]

pat = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\\\]|\\.)*)'\s*,?$", re.MULTILINE)

def has_cjk(s):
    for c in s:
        if ord(c) >= 0x4E00 and ord(c) <= 0x9FFF:
            return True
    return False

chinese_val = 0
english_val = 0
for m in pat.finditer(zh_section):
    key = m.group(1)
    val = m.group(2)
    if has_cjk(val):
        chinese_val += 1
    else:
        english_val += 1

print(f'_zh entries with Chinese values: {chinese_val}')
print(f'_zh entries with English values: {english_val}')

# Count _en entries
en_section = content[zh_end:]
en_count = sum(1 for _ in pat.finditer(en_section))
print(f'_en entries: {en_count}')
