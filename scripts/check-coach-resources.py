#!/usr/bin/env python3
"""Check only explicitly shipped neutral coach rules; never scan personal stores."""
from pathlib import Path
import re
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[1]
asset_root = root / 'apps/client/assets/coach'
expected = {f'{name}.md' for name in ('core', 'learning', 'review', 'interview', 'project')}
actual = {p.name for p in asset_root.iterdir() if p.is_file()}
errors = []
if actual != expected:
    errors.append(f'Unexpected coach rule inventory: {sorted(actual ^ expected)}')
manifest = (root / 'apps/client/pubspec.yaml').read_text()
if re.search(r'^\s*- assets/coach/\s*$', manifest, re.M):
    errors.append('Recursive coach asset inclusion is forbidden')
for name in sorted(expected):
    path = asset_root / name
    if not path.is_file() or path.is_symlink():
        errors.append(f'Missing or linked neutral resource: {name}')
        continue
    if f'assets/coach/{name}' not in manifest:
        errors.append(f'Resource missing from explicit asset manifest: {name}')
    text = path.read_text()
    for pattern in (r'/Users/[^/\s]+', r'/home/[^/\s]+', r'\.codex/(?:skills|sessions)',
                    r'(?i)(?:api[_ -]?key|bearer)\s*[:=]\s*[A-Za-z0-9_-]{12,}'):
        if re.search(pattern, text):
            errors.append(f'Local path or credential-like payload in {name}')
storage_assets = root / 'apps/client/web'
storage_manifest = json.loads((storage_assets / 'coach-storage-assets.json').read_text())
for name, expected_hash in storage_manifest['files'].items():
    if name not in {'sqlite3.wasm', 'drift_worker.js'}:
        errors.append(f'Unexpected storage runtime asset: {name}')
        continue
    if hashlib.sha256((storage_assets / name).read_bytes()).hexdigest() != expected_hash:
        errors.append(f'Storage runtime asset checksum mismatch: {name}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Coach resource allowlist passed: {len(expected)} neutral rule files; semantic review remains separate')
