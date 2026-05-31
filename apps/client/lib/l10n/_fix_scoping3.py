#!/usr/bin/env python3
"""Fix l10n scoping by tracking brace depth to find function boundaries."""
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

def find_function_bodies(lines):
    """Find all function/method bodies and their line ranges.
    Returns list of (start_line, open_brace_line, close_line, is_state_method, indent)."""
    results = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Skip comments
        if stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
            i += 1
            continue
        
        # Match function/method declarations
        # Pattern: [static] [return_type] name([params]) [async] {
        # Also handles: Widget _buildXxx(...) {, void _onTap() async {
        func_pattern = r'^(\s*)((?:static\s+)?(?:[\w<>,\?\s]+?)\s+)(\w+)\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?:async\s*)?\{'
        m = re.match(func_pattern, line)
        
        # Also match: name(params) { (without return type, like in constructors)
        if not m:
            func_pattern2 = r'^(\s*)(\w+)\s*\([^)]*\)\s*(?:async\s*)?\{'
            m = re.match(func_pattern2, line)
        
        if m:
            indent = m.group(1)
            func_name = m.group(3) if m.lastindex >= 3 else m.group(2)
            
            # Find the opening brace on this line or subsequent lines
            brace_line = i
            brace_col = line.rfind('{')
            if brace_col == -1:
                # Look for { on next lines
                for j in range(i + 1, min(i + 5, len(lines))):
                    if '{' in lines[j]:
                        brace_line = j
                        brace_col = lines[j].rfind('{')
                        break
            
            if brace_col == -1:
                i += 1
                continue
            
            # Count braces to find closing brace
            depth = 0
            close_line = -1
            for j in range(brace_line, len(lines)):
                for ch in lines[j]:
                    if ch == '{':
                        depth += 1
                    elif ch == '}':
                        depth -= 1
                        if depth == 0:
                            close_line = j
                            break
                if close_line >= 0:
                    break
            
            if close_line >= 0:
                results.append((i, brace_line, close_line, indent, func_name))
            i = close_line + 1 if close_line >= 0 else i + 1
        else:
            i += 1
    
    return results

def is_in_state_class(lines, func_start):
    """Check if the function is inside a State<...> class."""
    # Look backwards for class declaration
    for i in range(func_start - 1, max(0, func_start - 200), -1):
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
    
    # Check if file uses l10n.get
    has_l10n = any('l10n.get' in l for l in lines if not l.strip().startswith('//'))
    if not has_l10n:
        return 0
    
    changes = 0
    
    # Step 1: Add import if missing
    is_widget = '/widgets/' in filepath
    if 'localization_provider.dart' not in content:
        import_line = "import '../providers/localization_provider.dart';" if is_widget else "import '../../providers/localization_provider.dart';"
        # Find last import
        last_import_idx = -1
        for i, line in enumerate(lines):
            if line.strip().startswith('import '):
                last_import_idx = i
        if last_import_idx >= 0:
            lines.insert(last_import_idx + 1, import_line)
            changes += 1
    
    # Step 2: Remove const from lines with l10n.get()
    for i in range(len(lines)):
        if 'l10n.get' in lines[i] and 'const ' in lines[i]:
            lines[i] = re.sub(r'\bconst\s+', '', lines[i])
            changes += 1
    
    # Step 3: Remove const from parent containers that have l10n children
    # Find all lines with l10n.get and their parent const containers
    l10n_lines = set()
    for i, line in enumerate(lines):
        if 'l10n.get' in line and not line.strip().startswith('//'):
            l10n_lines.add(i)
    
    # For each line with l10n, check if it's inside a const container
    # by looking at the const keyword on ancestor lines
    # This is complex, so we'll use a simpler heuristic:
    # Remove const from any line that contains a child with l10n.get
    # We do this by checking if any line between i and the matching } has l10n.get
    
    # Actually, let's just remove const from common widget constructors
    # that might contain l10n children
    for i in range(len(lines)):
        if re.match(r'^\s*const\s+(Text|Icon|Tooltip|Chip|Badge|DataRow|DataCell|PopupMenuEntry|DropdownMenuItem|BottomNavigationBarItem|NavigationRailDestination|Tab|ActionChip|FilterChip|InputChip|ChoiceChip)\s*\(', lines[i]):
            lines[i] = re.sub(r'\bconst\s+', '', lines[i])
            changes += 1
    
    # Step 4: Find function bodies and add l10n declarations
    func_bodies = find_function_bodies(lines)
    
    # For each function, check if it uses l10n.get
    funcs_needing_l10n = []
    for (start, brace, close, indent, name) in func_bodies:
        has_usage = any(brace <= li <= close for li in l10n_lines)
        if not has_usage:
            continue
        
        # Check if l10n is already declared
        has_decl = False
        for j in range(brace, min(brace + 5, close + 1)):
            if 'final l10n' in lines[j] or 'var l10n' in lines[j] or 'late final l10n' in lines[j]:
                has_decl = True
                break
        
        if not has_decl:
            is_state = is_in_state_class(lines, start)
            funcs_needing_l10n.append((brace, indent + '  ', is_state))
    
    # Insert declarations from bottom to top
    funcs_needing_l10n.sort(key=lambda x: x[0], reverse=True)
    for (brace_line, indent, is_state) in funcs_needing_l10n:
        if is_state:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
        else:
            decl = f'{indent}final l10n = context.read<LocalizationProvider>();'
        lines.insert(brace_line + 1, decl)
        changes += 1
    
    # Step 5: Handle top-level l10n.get usage (outside any function)
    # Find lines with l10n.get that are NOT inside any function body
    func_ranges = [(b, c) for (_, b, c, _, _) in func_bodies]
    
    for i in range(len(lines)):
        if 'l10n.get' in lines[i] and not lines[i].strip().startswith('//'):
            in_func = any(b <= i <= c for (b, c) in func_ranges)
            if not in_func:
                # This is a top-level usage - needs special handling
                # Convert to a getter or lazy initialization
                # For now, mark it
                print(f"  ⚠️  Top-level l10n.get at line {i+1}: {lines[i].strip()[:80]}")
    
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
