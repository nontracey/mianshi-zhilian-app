#!/usr/bin/env python3
"""Fix ALL remaining l10n scoping issues:
1. Add l10n declaration to ALL methods that use l10n.get (not just build)
2. Remove 'const [' / 'const (' that contain l10n.get() within their scope
3. Handle State class getter for StatefulWidget
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
    """Remove string contents to avoid counting braces inside them."""
    result = re.sub(r"'[^']*'", "''", line)
    result = re.sub(r'"[^"]*"', '""', result)
    return result

def find_matching_close(lines, start_line, open_char, close_char):
    """Find the line with the matching close bracket/brace starting from start_line."""
    depth = 0
    for i in range(start_line, len(lines)):
        stripped = strip_strings(lines[i])
        for ch in stripped:
            if ch == open_char:
                depth += 1
            elif ch == close_char:
                depth -= 1
                if depth == 0:
                    return i
    return -1

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        return 0
    
    changes = 0
    
    # === Part 1: Remove 'const [' / 'const (' that contain l10n.get ===
    # Scan for lines with 'const [' or 'const (' and check if l10n.get is inside
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Check for 'const [' or 'const ('
        const_match = re.search(r'\bconst\s+(\[|\()', line)
        if const_match:
            open_char = const_match.group(1)
            close_char = ']' if open_char == '[' else ')'
            
            # Find the matching close
            close_line = find_matching_close(lines, i, open_char, close_char)
            if close_line > 0:
                # Check if l10n.get is anywhere between
                has_l10n_inside = False
                for j in range(i, close_line + 1):
                    if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                        has_l10n_inside = True
                        break
                
                if has_l10n_inside:
                    # Remove 'const ' from this line
                    old = lines[i]
                    lines[i] = re.sub(r'\bconst\s+', '', lines[i], count=1)
                    if lines[i] != old:
                        changes += 1
        i += 1
    
    # === Part 2: Add l10n declaration to ALL methods that use l10n.get ===
    # Strategy: find all function/method declarations (lines with `{` that look like functions)
    # and check if they contain l10n.get
    
    # First, find all class boundaries to know if we're in a State class
    class_ranges = []
    depth = 0
    cls_start = -1
    cls_name = ''
    is_state = False
    for i, line in enumerate(lines):
        stripped = strip_strings(line).strip()
        cls_match = re.match(r'class\s+(\w+)', stripped)
        if cls_match and depth == 0:
            cls_start = i
            cls_name = cls_match.group(1)
            is_state = bool(re.match(r'class\s+\w+\s+extends\s+State<', stripped))
        for ch in stripped:
            if ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and cls_start >= 0:
                    class_ranges.append((cls_start, i, is_state, cls_name))
                    cls_start = -1
    
    def is_in_state_class(line_num):
        for (cs, ce, iss, cn) in class_ranges:
            if cs <= line_num <= ce and iss:
                return True
        return False
    
    def has_l10n_decl_above(line_num, max_back=200):
        """Check if l10n is already declared in the enclosing scope."""
        depth = 0
        for j in range(line_num - 1, max(0, line_num - max_back), -1):
            stripped = strip_strings(lines[j])
            for ch in reversed(stripped):
                if ch == '}': depth += 1
                elif ch == '{': depth -= 1
            if depth < 0:
                break  # Exited enclosing block
            if re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j]):
                return True
        return False
    
    # Find method declarations and add l10n if needed
    # Process from bottom to top to avoid line number shifts
    insertions = []  # (line_num, indent, is_state)
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
            continue
        
        # Skip class/enum declarations
        if re.match(r'(?:abstract\s+)?class\s+\w+', stripped) or re.match(r'enum\s+\w+', stripped):
            continue
        
        # Look for method/function declarations: line with ( and {
        # Must have a function name before (
        has_brace = '{' in stripped
        has_paren = '(' in stripped
        
        if not has_brace:
            continue
        
        # Determine if this is a function/method declaration
        is_func = False
        if has_paren and has_brace:
            # Line has both ( and { - e.g., void foo() {
            paren_pos = stripped.find('(')
            brace_pos = stripped.find('{')
            if brace_pos > paren_pos:
                before_paren = stripped[:paren_pos].strip()
                if re.search(r'\w+\s*$', before_paren):
                    is_func = True
        elif has_brace and not has_paren:
            # Line has only { - could be multi-line function signature
            # Look backwards for (
            for j in range(i - 1, max(0, i - 10), -1):
                prev = lines[j].strip()
                if ')' in prev:
                    # Found closing paren
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
            continue
        
        # Skip if this is a class declaration line (class opening brace)
        if re.match(r'(?:abstract\s+)?class\s+\w+', stripped):
            continue
        
        # Check if this function contains l10n.get
        func_depth = 0
        has_usage = False
        for j in range(i, len(lines)):
            s = strip_strings(lines[j])
            for ch in s:
                if ch == '{': func_depth += 1
                elif ch == '}': func_depth -= 1
            if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                has_usage = True
            if func_depth == 0 and j > i:
                break
        
        if not has_usage:
            continue
        
        # Check if l10n is already declared
        if has_l10n_decl_above(i + 1):
            # Also check if l10n is declared right after the brace
            brace_line = i
            for j in range(i, min(i + 5, len(lines))):
                if '{' in lines[j]:
                    brace_line = j
                    break
            has_local_decl = False
            for j in range(brace_line, min(brace_line + 10, len(lines))):
                if re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j]):
                    has_local_decl = True
                    break
            if has_local_decl:
                continue
            # l10n is in enclosing scope (e.g., class-level getter) - OK
            continue
        
        # Need to add l10n declaration
        brace_line = i
        for j in range(i, min(i + 5, len(lines))):
            if '{' in lines[j]:
                brace_line = j
                break
        
        indent_match = re.match(r'^(\s*)', line)
        indent = (indent_match.group(1) if indent_match else '') + '  '
        in_state = is_in_state_class(i)
        insertions.append((brace_line, indent, in_state))
    
    # Insert from bottom to top
    insertions.sort(key=lambda x: x[0], reverse=True)
    for (brace_line, indent, in_state) in insertions:
        if in_state:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();\n'
        else:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();\n'
        lines.insert(brace_line + 1, decl)
        changes += 1
    
    # === Part 3: Also check build methods that were missed ===
    # (build methods that have l10n.get but no declaration)
    # Re-read since we modified lines
    i = 0
    extra_insertions = []
    while i < len(lines):
        line = lines[i]
        build_match = re.match(r'^(\s*)(?:@\w+\s+)?Widget\s+build\s*\(\s*BuildContext\s+\w+\s*\)', line)
        if build_match:
            indent = build_match.group(1) + '  '
            brace_line = i
            for j in range(i, min(i + 5, len(lines))):
                if '{' in lines[j]:
                    brace_line = j
                    break
            
            # Check if l10n is already declared nearby
            has_decl = False
            for j in range(brace_line, min(brace_line + 15, len(lines))):
                if re.search(r'\bfinal\s+l10n\b', lines[j]) or re.search(r'\bget\s+l10n\b', lines[j]):
                    has_decl = True
                    break
            
            if not has_decl:
                # Check if build method uses l10n
                d = 0
                has_usage = False
                for j in range(brace_line, len(lines)):
                    for ch in strip_strings(lines[j]):
                        if ch == '{': d += 1
                        elif ch == '}': d -= 1
                    if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                        has_usage = True
                    if d == 0 and j > brace_line:
                        break
                
                if has_usage:
                    extra_insertions.append((brace_line, indent))
        i += 1
    
    extra_insertions.sort(key=lambda x: x[0], reverse=True)
    for (brace_line, indent) in extra_insertions:
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
