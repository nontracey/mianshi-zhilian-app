#!/usr/bin/env python3
"""v2: Fix ALL l10n scoping issues reliably.
Strategy:
1. Remove 'const [' / 'const (' containing l10n.get
2. Find all functions that use l10n.get
3. For each, check if l10n is already accessible (class-level getter or local decl)
4. If not, add 'final l10n = context.watch<LocalizationProvider>();' after opening brace
"""
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

def find_matching_close_line(lines, start_line, open_ch, close_ch):
    depth = 0
    for i in range(start_line, len(lines)):
        for ch in strip_strings(lines[i]):
            if ch == open_ch: depth += 1
            elif ch == close_ch:
                depth -= 1
                if depth == 0: return i
    return -1

def find_function_body(lines, func_line):
    """Find the opening brace line and closing brace line of a function starting at func_line."""
    brace_line = -1
    for j in range(func_line, min(func_line + 10, len(lines))):
        if '{' in lines[j]:
            brace_line = j
            break
    if brace_line < 0:
        return -1, -1
    
    close_line = find_matching_close_line(lines, brace_line, '{', '}')
    return brace_line, close_line

def has_local_l10n(lines, start_line, end_line):
    """Check if l10n is declared as a local variable between start_line and end_line."""
    for j in range(start_line, min(end_line + 1, len(lines))):
        if re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j]):
            return True
    return False

def has_class_level_l10n(lines, class_start):
    """Check if the class at class_start has a class-level l10n getter."""
    for j in range(class_start, min(class_start + 10, len(lines))):
        if re.search(r'\bget\s+l10n\b', lines[j]):
            return True
        if '{' in lines[j]:
            break
    return False

def find_enclosing_class(lines, line_num):
    """Find the class that contains line_num. Returns (class_start, class_end, is_state)."""
    depth = 0
    for i in range(line_num, -1, -1):
        stripped = strip_strings(lines[i]).strip()
        for ch in reversed(stripped):
            if ch == '}': depth += 1
            elif ch == '{': depth -= 1
        if depth < 0:
            # Found the opening brace of the enclosing block
            # Check if this line or nearby lines have a class declaration
            for k in range(i, max(0, i - 3), -1):
                cls_match = re.match(r'\s*class\s+(\w+)', lines[k])
                if cls_match:
                    is_state = bool(re.search(r'extends\s+State<', lines[k]))
                    return k, is_state
            return -1, False
    return -1, False

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        return 0
    
    changes = 0
    
    # === Part 1: Remove 'const [' / 'const (' containing l10n.get ===
    i = 0
    while i < len(lines):
        line = lines[i]
        const_match = re.search(r'\bconst\s+(\[|\()', line)
        if const_match:
            open_ch = const_match.group(1)
            close_ch = ']' if open_ch == '[' else ')'
            close_line = find_matching_close_line(lines, i, open_ch, close_ch)
            if close_line > 0:
                has_l10n_inside = any(
                    'l10n.get' in lines[j] and not lines[j].strip().startswith('//')
                    for j in range(i, close_line + 1)
                )
                if has_l10n_inside:
                    old = lines[i]
                    lines[i] = re.sub(r'\bconst\s+', '', lines[i], count=1)
                    if lines[i] != old:
                        changes += 1
        i += 1
    
    # === Part 2: Find all functions and add l10n declarations ===
    # First, find all class boundaries with class-level l10n getters
    class_getters = set()  # Set of (class_start_line) that have class-level l10n getter
    depth = 0
    cls_start = -1
    for i, line in enumerate(lines):
        stripped = strip_strings(line).strip()
        cls_match = re.match(r'class\s+(\w+)', stripped)
        if cls_match and depth == 0:
            cls_start = i
        for ch in stripped:
            if ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and cls_start >= 0:
                    if has_class_level_l10n(lines, cls_start):
                        class_getters.add(cls_start)
                    cls_start = -1
    
    # Find all function declarations that use l10n.get
    # A function declaration is a line with ( and { where the part before ( looks like a function name
    insertions = []  # (brace_line, indent)
    
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
        has_paren = '(' in stripped
        has_brace = '{' in stripped
        
        if has_brace:
            if has_paren:
                paren_pos = stripped.find('(')
                brace_pos = stripped.find('{')
                if brace_pos > paren_pos:
                    before_paren = stripped[:paren_pos].strip()
                    if re.search(r'\w+\s*$', before_paren):
                        is_func = True
            else:
                # Only { - check if it's a multi-line function signature
                for j in range(i - 1, max(0, i - 10), -1):
                    prev = lines[j].strip()
                    if ')' in prev:
                        for k in range(j, max(0, j - 5), -1):
                            if '(' in lines[k]:
                                before_paren = lines[k].split('(')[0].strip()
                                if re.search(r'\w+\s*$', before_paren):
                                    is_func = True
                                break
                        break
                    elif prev == '' or not (prev.endswith(',') or prev.endswith('(')):
                        break
        
        if not is_func:
            i += 1
            continue
        
        # Find function body
        brace_line, close_line = find_function_body(lines, i)
        if brace_line < 0 or close_line < 0:
            i += 1
            continue
        
        # Check if this function uses l10n.get
        has_usage = any(
            'l10n.get' in lines[j] and not lines[j].strip().startswith('//')
            for j in range(brace_line, close_line + 1)
        )
        
        if not has_usage:
            i += 1
            continue
        
        # Check if l10n is already accessible
        # 1. Check if there's a local l10n declaration in this function
        if has_local_l10n(lines, brace_line + 1, close_line):
            i += 1
            continue
        
        # 2. Check if this function is inside a State class with class-level getter
        cls_start, is_state = find_enclosing_class(lines, i)
        if cls_start >= 0 and cls_start in class_getters:
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
        decl = f'{indent}final l10n = context.watch<LocalizationProvider>();\n'
        lines.insert(brace_line + 1, decl)
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
        if changes > 0:
            print(f"✅ {f}: +{changes} fixes")
        else:
            print(f"⏭️  {f}: already OK")
    print(f"\nTotal: {total} fixes")

if __name__ == '__main__':
    main()
