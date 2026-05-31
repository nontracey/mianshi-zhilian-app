#!/usr/bin/env python3
"""v3: Fix ALL l10n scoping issues. Simple and reliable approach."""
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

def strip_strings(line):
    result = re.sub(r"'[^']*'", "''", line)
    result = re.sub(r'"[^"]*"', '""', result)
    return result

def find_matching_close(lines, start, open_ch, close_ch):
    depth = 0
    for i in range(start, len(lines)):
        for ch in strip_strings(lines[i]):
            if ch == open_ch: depth += 1
            elif ch == close_ch:
                depth -= 1
                if depth == 0: return i
    return -1

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if not any('l10n.get' in l for l in lines if not l.strip().startswith('//')):
        return 0
    
    changes = 0
    
    # === Step 1: Remove 'const [' / 'const (' containing l10n.get ===
    i = 0
    while i < len(lines):
        m = re.search(r'\bconst\s+(\[|\()', lines[i])
        if m:
            open_ch = m.group(1)
            close_ch = ']' if open_ch == '[' else ')'
            close_line = find_matching_close(lines, i, open_ch, close_ch)
            if close_line > 0:
                if any('l10n.get' in lines[j] and not lines[j].strip().startswith('//')
                       for j in range(i, close_line + 1)):
                    old = lines[i]
                    lines[i] = re.sub(r'\bconst\s+', '', lines[i], count=1)
                    if lines[i] != old:
                        changes += 1
        i += 1
    
    # === Step 2: Build class map (forward pass) ===
    class_map = {}  # line_num -> (class_start, has_getter)
    depth = 0
    cls_start = -1
    has_getter = False
    for i, line in enumerate(lines):
        stripped = strip_strings(line).strip()
        if re.match(r'class\s+\w+', stripped) and depth == 0:
            cls_start = i
            has_getter = False
        if re.search(r'\bget\s+l10n\b', line) and depth >= 1:
            has_getter = True
        for ch in stripped:
            if ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and cls_start >= 0:
                    for k in range(cls_start, i + 1):
                        class_map[k] = (cls_start, has_getter)
                    cls_start = -1
    
    # === Step 3: Find functions that use l10n.get and need declarations ===
    insertions = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        if not stripped or stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
            i += 1
            continue
        
        # Skip class/enum declarations
        if re.match(r'(?:abstract\s+)?class\s+\w+', stripped) or re.match(r'enum\s+\w+', stripped):
            i += 1
            continue
        
        # Check if this is a function declaration
        is_func = False
        has_brace = '{' in stripped
        
        if has_brace:
            has_paren = '(' in stripped
            if has_paren:
                paren_pos = stripped.find('(')
                brace_pos = stripped.find('{')
                if brace_pos > paren_pos:
                    before_paren = stripped[:paren_pos].strip()
                    if re.search(r'\w+\s*$', before_paren):
                        is_func = True
            else:
                for j in range(i - 1, max(0, i - 10), -1):
                    prev = lines[j].strip()
                    if ')' in prev:
                        for k in range(j, max(0, j - 5), -1):
                            if '(' in lines[k]:
                                bp = lines[k].split('(')[0].strip()
                                if re.search(r'\w+\s*$', bp):
                                    is_func = True
                                break
                        break
                    elif prev == '' or not (prev.endswith(',') or prev.endswith('(')):
                        break
        
        if not is_func:
            i += 1
            continue
        
        # Find function body
        brace_line = i
        for j in range(i, min(i + 10, len(lines))):
            if '{' in lines[j]:
                brace_line = j
                break
        
        close_line = find_matching_close(lines, brace_line, '{', '}')
        if close_line < 0:
            i += 1
            continue
        
        # Check if function uses l10n.get
        if not any('l10n.get' in lines[j] and not lines[j].strip().startswith('//')
                   for j in range(brace_line, close_line + 1)):
            i += 1
            continue
        
        # Check if l10n is already declared locally in this function
        if any(re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j])
               for j in range(brace_line + 1, min(brace_line + 20, close_line + 1))):
            i += 1
            continue
        
        # Check if enclosing class has class-level getter
        if i in class_map:
            _, cls_has_getter = class_map[i]
            if cls_has_getter:
                i += 1
                continue
        
        # Need to add l10n declaration
        indent_match = re.match(r'^(\s*)', line)
        indent = (indent_match.group(1) if indent_match else '') + '  '
        insertions.append((brace_line, indent))
        i += 1
    
    # Insert from bottom to top
    insertions.sort(key=lambda x: x[0], reverse=True)
    for (brace_line, indent) in insertions:
        lines.insert(brace_line + 1, f'{indent}final l10n = context.watch<LocalizationProvider>();\n')
        changes += 1
    
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
        print(f"{'✅' if changes else '⏭️'} {f}: {'+' + str(changes) if changes else 'OK'}")
    print(f"\nTotal: {total} fixes")

if __name__ == '__main__':
    main()
