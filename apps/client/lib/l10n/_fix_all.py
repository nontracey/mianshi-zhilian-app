#!/usr/bin/env python3
"""Comprehensive fix script: handles scoping, imports, const removal, and edge cases."""
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

IMPORT_LINE = "import '../../providers/localization_provider.dart';\n"
IMPORT_LINE_WIDGETS = "import '../providers/localization_provider.dart';\n"

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    has_l10n = any('l10n.get' in l for l in lines)
    if not has_l10n:
        return 0
    
    is_widget = '/widgets/' in filepath
    import_line = IMPORT_LINE_WIDGETS if is_widget else IMPORT_LINE
    
    changes = 0
    
    # 1. Add import if missing
    if 'localization_provider.dart' not in content:
        # Find last import line
        last_import = 0
        for i, line in enumerate(lines):
            if line.strip().startswith('import '):
                last_import = i
        lines.insert(last_import + 1, import_line.rstrip())
        changes += 1
    
    # 2. Remove const from lines containing l10n.get()
    new_lines = []
    for line in lines:
        if 'l10n.get' in line and 'const ' in line:
            # Remove const that directly precedes a widget constructor
            line = re.sub(r'\bconst\s+(Text|Icon|Tooltip|Chip|Badge|PopupMenuEntry|DataRow|DataCell)\s*\(', r'\1(', line)
            # Remove const before Padding/Container/Row/Column/SizedBox/Padding that contain l10n children
            # (we'll handle parent const in a separate pass)
            changes += 1
        new_lines.append(line)
    lines = new_lines
    
    # 3. Find all functions/methods that use l10n.get and need scoping
    # Strategy: for each line with l10n.get, find the enclosing function/method
    # and check if it has a l10n declaration
    
    # First, identify all function/method boundaries
    func_ranges = []  # (start_line, end_line, brace_line, is_state_class_method, name)
    brace_depth = 0
    in_function = False
    func_start = -1
    func_brace = -1
    func_name = ''
    class_name = ''
    in_class = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Track class declarations
        class_match = re.match(r'class\s+(\w+)', stripped)
        if class_match:
            class_name = class_match.group(1)
            in_class = True
        
        # Track function/method declarations
        # Match: type name(params) { or type name(params) async {
        func_match = re.match(
            r'(?:static\s+|Future\s+|void\s+|Widget\s+|String\s+|int\s+|double\s+|bool\s+|List\s*<[^>]+>\s+|Map\s*<[^>]+>\s+|dynamic\s+|Color\s+|IconData\s+|EdgeInsets\s+|Size\s+|Duration\s+|DateTime\s+|[\w<>,]+\s+)*'
            r'(\w+)\s*(?:<[^>]+>)?\s*\([^)]*\)\s*(?:async\s*)?(?:=>\s*[^;{]*[;{]|\{)',
            stripped
        )
        if func_match and not stripped.startswith('//') and not stripped.startswith('if ') and not stripped.startswith('for ') and not stripped.startswith('while '):
            func_name = func_match.group(1)
            # Check if this line has an opening brace
            if '{' in stripped:
                # Find the position of the opening brace
                brace_count = 0
                for j, ch in enumerate(stripped):
                    if ch == '{':
                        brace_count += 1
                    elif ch == '}':
                        brace_count -= 1
                if brace_count > 0:
                    # This function opens a brace
                    func_start = i
                    func_brace = i
                    in_function = True
                    brace_depth = brace_count
            elif '{' not in stripped and stripped.endswith('{'):
                func_start = i
                func_brace = i
                in_function = True
                brace_depth = 1
        
        # Also match arrow functions that span to end of line
        if not in_function and '=>' in stripped and '{' not in stripped:
            # Arrow function, skip
            pass
        
        # Track brace depth
        if in_function:
            for ch in stripped:
                if ch == '{':
                    if func_brace == -1:
                        func_brace = i
                    brace_depth += stripped.count('{')
                elif ch == '}':
                    brace_depth -= stripped.count('}')
            
            if brace_depth <= 0 and func_start >= 0:
                is_state = 'State<' in class_name or class_name.endswith('State')
                func_ranges.append((func_start, i, func_brace, is_state, func_name))
                in_function = False
                func_start = -1
                func_brace = -1
                brace_depth = 0
    
    # 4. For each function that uses l10n.get, check if it has l10n declaration
    # If not, add one after the opening brace
    lines_with_l10n = set()
    for i, line in enumerate(lines):
        if 'l10n.get' in line and not line.strip().startswith('//'):
            lines_with_l10n.add(i)
    
    # Find which functions contain l10n.get usage
    funcs_needing_l10n = []
    for (start, end, brace, is_state, name) in func_ranges:
        has_l10n_usage = any(start <= li <= end for li in lines_with_l10n)
        if not has_l10n_usage:
            continue
        
        # Check if l10n is already declared in this function
        has_decl = False
        for i in range(start, min(end + 1, start + 10)):
            if i < len(lines) and ('final l10n' in lines[i] or 'var l10n' in lines[i] or 'LocalizationProvider l10n' in lines[i]):
                has_decl = True
                break
        
        if not has_decl:
            funcs_needing_l10n.append((start, end, brace, is_state, name))
    
    # Insert l10n declarations (from bottom to top to preserve line numbers)
    funcs_needing_l10n.sort(key=lambda x: x[2], reverse=True)
    for (start, end, brace, is_state, name) in funcs_needing_l10n:
        indent = ''
        if brace < len(lines):
            m = re.match(r'^(\s*)', lines[brace])
            if m:
                indent = m.group(1) + '  '
        
        if is_state:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
        else:
            decl = f'{indent}final l10n = context.read<LocalizationProvider>();'
        
        # Insert after the line with opening brace
        insert_at = brace + 1
        if insert_at < len(lines):
            lines.insert(insert_at, decl)
            changes += 1
    
    # 5. Handle top-level l10n.get usage (outside any function)
    # These are typically in top-level variable declarations or const lists
    # We need to convert them to use a different approach
    # For now, just flag them - they need manual intervention
    
    # Write back
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
