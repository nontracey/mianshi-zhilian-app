#!/usr/bin/env python3
"""Fix l10n scoping: add l10n to ALL methods that use it, handling multi-line signatures."""
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
    
    # First pass: find all method ranges and whether they use l10n
    method_ranges = []  # (start_line, end_line, has_l10n_def, uses_l10n)
    i = 0
    while i < len(lines):
        line = lines[i]
        # Detect method start (simplified: look for method signature ending with {)
        # This handles multi-line signatures by looking for the opening brace
        if re.match(r'^\s+(?:void|Widget|String|List|Map|bool|int|double|Future|dynamic)\s+\w+\s*\(', line):
            method_start = i
            # Find the opening brace
            j = i
            brace_found = False
            while j < min(i + 10, len(lines)):  # Look up to 10 lines ahead
                if '{' in lines[j]:
                    brace_found = True
                    break
                j += 1
            
            if brace_found:
                # Find the end of this method
                brace_count = 0
                k = j
                while k < len(lines):
                    brace_count += lines[k].count('{') - lines[k].count('}')
                    if brace_count <= 0:
                        break
                    k += 1
                
                method_end = k
                method_text = ''.join(lines[method_start:method_end+1])
                has_l10n_def = 'final l10n = context.' in method_text and 'LocalizationProvider' in method_text
                uses_l10n = 'l10n.get(' in method_text or 'l10n.getp(' in method_text
                
                method_ranges.append((method_start, method_end, has_l10n_def, uses_l10n))
                i = method_end + 1
                continue
        i += 1
    
    # Second pass: add l10n to methods that need it
    new_lines = []
    i = 0
    method_idx = 0
    changed = False
    
    while i < len(lines):
        if method_idx < len(method_ranges) and i == method_ranges[method_idx][0]:
            start, end, has_l10n_def, uses_l10n = method_ranges[method_idx]
            
            # Add all lines of this method
            for j in range(start, end + 1):
                new_lines.append(lines[j])
                # After the opening brace, add l10n if needed
                if j >= start and '{' in lines[j] and uses_l10n and not has_l10n_def:
                    # Check if this is the line with the opening brace
                    if j == start or (j > start and '{' in lines[j] and '}' not in lines[j]):
                        indent = re.match(r'^(\s*)', lines[j]).group(1)
                        new_lines.append(f'{indent}  final l10n = context.read<LocalizationProvider>();\n')
                        changed = True
                        has_l10n_def = True  # Only add once
            
            i = end + 1
            method_idx += 1
        else:
            new_lines.append(lines[i])
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
