#!/usr/bin/env python3
"""Fix l10n scoping: add l10n variable to all methods/functions that use l10n.get() but don't define it."""
import re, os

BASE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib'

FILES = [
    'widgets/header_bar.dart',
    'widgets/navigation_rail_panel.dart',
    'widgets/voice_input_button.dart',
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
    
    # Find all lines that use l10n.get or l10n.getp
    l10n_usage_lines = set()
    for i, line in enumerate(lines):
        if 'l10n.get(' in line or 'l10n.getp(' in line:
            l10n_usage_lines.add(i)
    
    if not l10n_usage_lines:
        return False
    
    # Find all method/function definitions and their scope
    # We need to add l10n variable to methods that use l10n but don't define it
    new_lines = []
    i = 0
    changed = False
    
    while i < len(lines):
        line = lines[i]
        
        # Detect method/function start (simplified)
        # Look for lines like: void _methodName(...) { or Widget build(BuildContext context) {
        method_match = re.match(r'^(\s+)((?:void|Widget|String|List|Map|bool|int|double|Future|dynamic)\s+\w+\s*\([^)]*\)\s*(?:async\s*)?\{)', line)
        
        if method_match:
            indent = method_match.group(1)
            method_sig = method_match.group(2)
            
            # Check if this method uses l10n by looking ahead
            brace_count = line.count('{') - line.count('}')
            j = i + 1
            method_uses_l10n = False
            method_has_l10n_def = False
            
            while j < len(lines) and brace_count > 0:
                brace_count += lines[j].count('{') - lines[j].count('}')
                if 'l10n.get(' in lines[j] or 'l10n.getp(' in lines[j]:
                    method_uses_l10n = True
                if 'final l10n = context.' in lines[j] and 'LocalizationProvider' in lines[j]:
                    method_has_l10n_def = True
                j += 1
            
            # If method uses l10n but doesn't define it, add l10n variable
            if method_uses_l10n and not method_has_l10n_def:
                new_lines.append(line)
                # Add l10n variable after method signature
                if '{' in line:
                    # Method signature and opening brace on same line
                    new_lines.append(f'{indent}  final l10n = context.read<LocalizationProvider>();\n')
                else:
                    # Opening brace on next line - add after it
                    i += 1
                    if i < len(lines):
                        new_lines.append(lines[i])  # The { line
                        new_lines.append(f'{indent}  final l10n = context.read<LocalizationProvider>();\n')
                changed = True
                i += 1
                continue
        
        # Also handle builder functions like: builder: (context) {
        builder_match = re.match(r'^(\s+)(builder:\s*\(context\)\s*\{)', line)
        if builder_match:
            indent = builder_match.group(1)
            # Check if this builder uses l10n
            brace_count = line.count('{') - line.count('}')
            j = i + 1
            builder_uses_l10n = False
            builder_has_l10n = False
            
            while j < len(lines) and brace_count > 0:
                brace_count += lines[j].count('{') - lines[j].count('}')
                if 'l10n.get(' in lines[j] or 'l10n.getp(' in lines[j]:
                    builder_uses_l10n = True
                if 'final l10n = context.' in lines[j] and 'LocalizationProvider' in lines[j]:
                    builder_has_l10n = True
                j += 1
            
            if builder_uses_l10n and not builder_has_l10n:
                new_lines.append(line)
                new_lines.append(f'{indent}  final l10n = context.watch<LocalizationProvider>();\n')
                changed = True
                i += 1
                continue
        
        new_lines.append(line)
        i += 1
    
    if changed:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
    
    return changed


def main():
    for f in FILES:
        path = os.path.join(BASE, f)
        if os.path.exists(path):
            changed = fix_file(path)
            print(f"{'✅' if changed else '⏭️'} {f}")
        else:
            print(f"❌ {f}")


if __name__ == '__main__':
    main()
