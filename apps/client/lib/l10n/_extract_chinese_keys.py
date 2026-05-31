#!/usr/bin/env python3
"""
l10n Key Convention Checker

Checks that NO Dart file in the project uses Chinese strings as l10n keys.
l10n keys must be English identifiers (snake_case), because:
- Keys are the stable identifier; values (translations) can change.
- Chinese keys violate the separation of key and value.
- Chinese keys prevent automated tooling and confuse contributors.

Usage:
    python3 _extract_chinese_keys.py
    # Exits with 0 if clean, 1 if any Chinese keys found.
"""
import re, os, sys

BASE = os.path.join(os.path.dirname(__file__), '..')

all_keys = set()
files_with_issues = set()

for root, dirs, files in os.walk(BASE):
    # Skip hidden dirs and generated files
    dirs[:] = [d for d in dirs if not d.startswith('.')]
    for f in files:
        if not f.endswith('.dart'):
            continue
        path = os.path.join(root, f)
        with open(path, 'r', encoding='utf-8') as fh:
            content = fh.read()
        for m in re.finditer(r"l10n\.(?:get|getp)\('([^']*[\u4e00-\u9fff][^']*)'", content):
            all_keys.add(m.group(1))
            files_with_issues.add(path)

if not all_keys:
    print('✅  All l10n keys use English identifiers. No Chinese keys found.')
    sys.exit(0)

print(f'❌  Found {len(all_keys)} Chinese l10n key(s) across {len(files_with_issues)} file(s):\n')
for k in sorted(all_keys):
    print(f'   - {repr(k)}')
print()
for f in sorted(files_with_issues):
    rel = os.path.relpath(f, BASE)
    print(f'   File: {rel}')
print()
print('Keys must be English identifiers (snake_case), not Chinese strings.')
sys.exit(1)
