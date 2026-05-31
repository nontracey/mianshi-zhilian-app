import re

with open('lib/l10n/l10n.dart') as f:
    content = f.read()

zh_start = content.find('static const _zh = {')
zh_end = content.find('static const _en = {')
zh_text = content[zh_start:zh_end]

pat = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\\\]|\\.)*)'\s*,?$", re.MULTILINE)

for m in pat.finditer(zh_text):
    if m.group(1) == 'text_ea189e1f':
        print(f'Key: {m.group(1)}')
        print(f'Value: {m.group(2)[:80]}')
        break
else:
    print('Key not found')
