#!/usr/bin/env python3
"""v2: Fix l10n scoping using proper brace-depth tracking for ALL code blocks."""
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

def find_enclosing_function(lines, target_line):
    """Find the function/method that encloses target_line by tracking brace depth."""
    # Start from target_line and go backwards to find the function declaration
    # Then verify by counting braces
    
    # First, find all opening braces and their depths going backwards
    depth = 0
    for i in range(target_line, -1, -1):
        line = lines[i]
        # Count braces on this line (going backwards)
        for ch in reversed(line):
            if ch == '}':
                depth += 1
            elif ch == '{':
                depth -= 1
                if depth < 0:
                    # This { opens a block. Check if this line is a function declaration
                    stripped = line.strip()
                    # Check for function/method patterns
                    if re.match(r'(?:static\s+)?(?:[\w<>,\?\s]+?)\s+\w+\s*(?:<[^>]*>)?\s*\(', stripped):
                        return i
                    # Check for simpler patterns like: name(params) {
                    if re.match(r'\w+\s*\(', stripped) and '{' in stripped:
                        return i
                    # Check for arrow function: => ... {
                    # Check for closure: (...) {
                    # Just return the line that has the opening brace
                    return i
    
    return -1

def is_in_state_class(lines, func_line):
    """Check if func_line is inside a State<...> class."""
    for i in range(func_line - 1, max(0, func_line - 300), -1):
        stripped = lines[i].strip()
        if re.match(r'class\s+\w+\s+extends\s+State<', stripped):
            return True
        if re.match(r'class\s+\w+', stripped):
            return False
    return False

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        return 0
    
    changes = 0
    
    # Step 1: Add import
    is_widget = '/widgets/' in filepath
    if 'localization_provider.dart' not in content:
        import_line = "import '../providers/localization_provider.dart';" if is_widget else "import '../../providers/localization_provider.dart';"
        last_import = -1
        for i, line in enumerate(lines):
            if line.strip().startswith('import '):
                last_import = i
        if last_import >= 0:
            lines.insert(last_import + 1, import_line)
            changes += 1
    
    # Step 2: Remove const from lines with l10n.get()
    for i in range(len(lines)):
        if 'l10n.get' in lines[i]:
            old = lines[i]
            lines[i] = re.sub(r'\bconst\s+', '', lines[i])
            if lines[i] != old:
                changes += 1
    
    # Step 3: Find all lines with l10n.get and their enclosing functions
    l10n_lines = []
    for i, line in enumerate(lines):
        if 'l10n.get' in line and not line.strip().startswith('//'):
            l10n_lines.append(i)
    
    # For each l10n line, find its enclosing function
    func_map = {}  # func_line -> (is_state, [l10n_lines_in_func])
    for ll in l10n_lines:
        func_line = find_enclosing_function(lines, ll)
        if func_line < 0:
            # Top-level usage - skip for now
            continue
        if func_line not in func_map:
            is_state = is_in_state_class(lines, func_line)
            func_map[func_line] = (is_state, [])
        func_map[func_line][1].append(ll)
    
    # Step 4: For each function, check if l10n is already declared
    # Insert declarations from bottom to top
    insertions = []
    for func_line, (is_state, l10n_lines_in) in func_map.items():
        # Find the opening brace line
        brace_line = func_line
        for i in range(func_line, min(func_line + 5, len(lines))):
            if '{' in lines[i]:
                brace_line = i
                break
        
        # Check if l10n is already declared in the first 10 lines after brace
        has_decl = False
        for j in range(brace_line, min(brace_line + 10, len(lines))):
            if 'final l10n' in lines[j] or 'var l10n' in lines[j] or 'late final l10n' in lines[j]:
                has_decl = True
                break
        
        if not has_decl:
            indent_match = re.match(r'^(\s*)', lines[brace_line])
            indent = (indent_match.group(1) if indent_match else '') + '  '
            
            if is_state:
                decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
            else:
                decl = f'{indent}final l10n = context.read<LocalizationProvider>();'
            
            insertions.append((brace_line + 1, decl))
    
    # Sort by line number descending to preserve indices
    insertions.sort(key=lambda x: x[0], reverse=True)
    for line_num, decl in insertions:
        lines.insert(line_num, decl)
        changes += 1
    
    # Step 5: Handle top-level l10n.get usage
    # These are outside any function - need to be handled differently
    # Rebuild func ranges after insertions
    # For now, just report them
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    
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
            print(f"✅ {f}: {changes} fixes")
        else:
            print(f"⏭️  {f}: no fixes needed")
    print(f"\nTotal: {total} fixes")

if __name__ == '__main__':
    main()
