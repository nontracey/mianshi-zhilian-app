#!/usr/bin/env python3
"""Simple approach: Add l10n declarations to State class methods and StatelessWidget build methods."""
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
    
    # Step 3: Find State classes and add l10n to all their methods
    # Strategy: find "class _XxxState extends State<Yyy>" and then find all
    # method declarations within that class. For each method, if it contains
    # l10n.get, add l10n declaration after the opening brace.
    
    # First, find all class boundaries
    class_ranges = []  # (class_start, class_end, is_state, class_name)
    depth = 0
    class_start = -1
    class_name = ''
    is_state = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Track class declarations
        cls_match = re.match(r'class\s+(\w+)', stripped)
        if cls_match and depth == 0:
            class_start = i
            class_name = cls_match.group(1)
            is_state = bool(re.match(r'class\s+\w+\s+extends\s+State<', stripped))
        
        # Track brace depth
        for ch in stripped:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0 and class_start >= 0:
                    class_ranges.append((class_start, i, is_state, class_name))
                    class_start = -1
    
    # Step 4: For each State class, find methods and add l10n
    for (cls_start, cls_end, is_state_cls, cls_name) in class_ranges:
        if not is_state_cls:
            continue
        
        # Find all method declarations in this class
        method_depth = 0
        in_method = False
        method_start = -1
        method_brace = -1
        
        for i in range(cls_start + 1, cls_end):
            line = lines[i]
            stripped = line.strip()
            
            if not in_method:
                # Look for method declarations
                # Pattern: [static] [return_type] name([params]) [async] {
                # Or: Widget _buildXxx(...) {
                method_match = re.match(
                    r'^\s+((?:static\s+)?(?:[\w<>,\?\s]+?)\s+)(\w+)\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?:async\s*)?\{',
                    line
                )
                if method_match:
                    method_name = method_match.group(2)
                    in_method = True
                    method_start = i
                    method_brace = i
                    method_depth = 1
                    
                    # Check if this method contains l10n.get
                    has_l10n_in_method = False
                    check_depth = 1
                    for j in range(i + 1, cls_end):
                        for ch in lines[j]:
                            if ch == '{':
                                check_depth += 1
                            elif ch == '}':
                                check_depth -= 1
                                if check_depth == 0:
                                    break
                        if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                            has_l10n_in_method = True
                        if check_depth == 0:
                            break
                    
                    if has_l10n_in_method:
                        # Check if l10n is already declared
                        has_decl = False
                        for j in range(i, min(i + 10, cls_end)):
                            if 'final l10n' in lines[j] or 'var l10n' in lines[j]:
                                has_decl = True
                                break
                        
                        if not has_decl:
                            indent_match = re.match(r'^(\s*)', line)
                            indent = (indent_match.group(1) if indent_match else '') + '  '
                            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
                            lines.insert(i + 1, decl)
                            changes += 1
                            # Adjust cls_end since we inserted a line
                            cls_end += 1
                    
                    in_method = False
                    method_start = -1
                    method_brace = -1
    
    # Step 5: Handle StatelessWidget build methods
    for (cls_start, cls_end, is_state_cls, cls_name) in class_ranges:
        if is_state_cls:
            continue
        
        # Find build method
        for i in range(cls_start + 1, cls_end):
            if re.match(r'^\s+(?:@\w+\s+)?Widget\s+build\s*\(', lines[i]):
                # Check if it contains l10n.get
                has_l10n_in_build = False
                depth = 0
                for j in range(i, cls_end):
                    for ch in lines[j]:
                        if ch == '{':
                            depth += 1
                        elif ch == '}':
                            depth -= 1
                    if 'l10n.get' in lines[j] and not lines[j].strip().startswith('//'):
                        has_l10n_in_build = True
                    if depth == 0 and j > i:
                        break
                
                if has_l10n_in_build:
                    # Find the opening brace
                    brace_line = i
                    for j in range(i, min(i + 5, cls_end)):
                        if '{' in lines[j]:
                            brace_line = j
                            break
                    
                    # Check if l10n is already declared
                    has_decl = False
                    for j in range(brace_line, min(brace_line + 10, cls_end)):
                        if 'final l10n' in lines[j] or 'var l10n' in lines[j]:
                            has_decl = True
                            break
                    
                    if not has_decl:
                        indent_match = re.match(r'^(\s*)', lines[brace_line])
                        indent = (indent_match.group(1) if indent_match else '') + '  '
                        decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
                        lines.insert(brace_line + 1, decl)
                        changes += 1
    
    # Step 6: Handle top-level functions that use l10n.get
    # These are outside any class - need to be passed l10n as parameter
    # For now, find them and add l10n using context.read
    # Actually, top-level functions don't have context. We need to handle these differently.
    
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
