#!/usr/bin/env python3
"""Fix: Add 'final l10n = context.watch<LocalizationProvider>();' to build methods that use l10n.get but don't declare l10n."""
import re, os

BASE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib'

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

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        return 0
    
    changes = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Find build methods: "Widget build(BuildContext context) {"
        # or "Widget build(BuildContext context) {" on same line
        # or multi-line build methods ending with "{"
        build_match = re.match(r'^(\s*)(?:@\w+\s+)?Widget\s+build\s*\(\s*BuildContext\s+\w+\s*\)', line)
        if not build_match:
            i += 1
            continue
        
        indent = build_match.group(1) + '  '
        
        # Find the opening brace (might be on this line or next lines)
        brace_line = i
        brace_found = '{' in line
        if not brace_found:
            for j in range(i + 1, min(i + 5, len(lines))):
                if '{' in lines[j]:
                    brace_line = j
                    brace_found = True
                    break
        
        if not brace_found:
            i += 1
            continue
        
        # Check if l10n is already declared in first 15 lines after brace
        has_decl = False
        for j in range(brace_line, min(brace_line + 15, len(lines))):
            if re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j]):
                has_decl = True
                break
        
        if has_decl:
            i = brace_line + 1
            continue
        
        # Check if this build method contains l10n.get
        depth = 0
        has_usage = False
        for j in range(brace_line, len(lines)):
            for ch in lines[j]:
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
            if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                has_usage = True
            if depth == 0 and j > brace_line:
                break
        
        if not has_usage:
            i = brace_line + 1
            continue
        
        # Insert l10n declaration after the brace line
        decl = f'{indent}final l10n = context.watch<LocalizationProvider>();\n'
        lines.insert(brace_line + 1, decl)
        changes += 1
        i = brace_line + 2  # Skip past the inserted line
    
    if changes > 0:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(lines)
    
    return changes

def main():
    total = 0
    for f in FILES:
        path = os.path.join(BASE, f)
        if not os.path.exists(path):
            print(f"❌ {f}")
            continue
        changes = fix_file(path)
        total += changes
        if changes > 0:
            print(f"✅ {f}: +{changes} l10n declarations")
        else:
            print(f"⏭️  {f}: already OK")
    print(f"\nTotal: {total} declarations added")

if __name__ == '__main__':
    main()
