#!/usr/bin/env python3
"""v6: Fix l10n scoping by processing top-to-bottom, inserting as we go.
No pre-computed block tracking - uses lookahead to check if a block needs l10n."""
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

def block_has_l10n(lines, start_idx):
    """Check if the block starting at start_idx (line with {) contains l10n.get().
    Returns True if l10n.get is found before the matching }."""
    depth = 0
    for i in range(start_idx, len(lines)):
        stripped = strip_strings(lines[i])
        for ch in stripped:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return False  # Reached end of block without finding l10n
        if 'l10n.get' in lines[i] and not lines[i].strip().startswith('//'):
            return True
    return False

def is_class_or_enum(line):
    """Check if line is a class/enum declaration."""
    stripped = line.strip()
    return bool(re.match(r'(?:abstract\s+)?class\s+\w+', stripped) or re.match(r'enum\s+\w+', stripped))

def is_function_or_method(lines, line_idx):
    """Check if line at line_idx looks like a function/method declaration."""
    line = lines[line_idx]
    stripped = line.strip()
    if stripped.startswith('//') or stripped.startswith('/*'):
        return False
    
    # Exclude control flow statements
    if re.match(r'(?:if|for|while|switch|try|catch|finally|else|do)\s*[\({]', stripped):
        return False
    if stripped.startswith('switch '):
        return False
    
    # Exclude closures/callbacks: lines starting with ( or )
    if stripped.startswith('(') or stripped.startswith(')'):
        return False
    
    # Case 1: Line has both ( and { - e.g., void foo() {
    paren_pos = stripped.find('(')
    brace_pos = stripped.find('{')
    if paren_pos >= 0 and brace_pos > paren_pos:
        before_paren = stripped[:paren_pos].strip()
        if re.search(r'\w+\s*$', before_paren):
            return True
    
    # Case 2: Line has only { - could be multi-line function signature
    # e.g., void foo(\n  int param,\n) {
    if '{' in stripped and '(' not in stripped:
        # Look backwards for a line with ( that's part of the function signature
        for j in range(line_idx - 1, max(0, line_idx - 10), -1):
            prev = lines[j].strip()
            if ')' in prev and '(' in prev:
                # Found the closing paren of the parameter list
                # Check if there's a function name before the opening paren
                # Look further back for the function name
                for k in range(j, max(0, j - 5), -1):
                    if '(' in lines[k]:
                        before_paren = lines[k].split('(')[0].strip()
                        if re.search(r'\w+\s*$', before_paren):
                            return True
                        break
                break
            elif prev == '' or (not prev.endswith(',') and not prev.endswith('(')):
                break
    
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
    
    # Step 3: Process top-to-bottom, inserting l10n declarations
    # We process from top to bottom, so insertions shift subsequent indices
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Skip if this line doesn't have {
        if '{' not in stripped:
            i += 1
            continue
        
        # Skip class/enum declarations
        if is_class_or_enum(stripped):
            i += 1
            continue
        
        # Skip if already has l10n declaration
        if 'final l10n' in stripped or 'var l10n' in stripped:
            i += 1
            continue
        
        # Check if this looks like a function/method
        if not is_function_or_method(lines, i):
            i += 1
            continue
        
        # Check if this block contains l10n.get
        if not block_has_l10n(lines, i):
            i += 1
            continue
        
        # Check if l10n is already declared in the first 10 lines of the block
        has_decl = False
        for j in range(i, min(i + 10, len(lines))):
            if 'final l10n' in lines[j] or 'var l10n' in lines[j] or 'late final l10n' in lines[j]:
                has_decl = True
                break
        
        # Also check if l10n is declared in the enclosing function (look backwards)
        if not has_decl:
            depth_back = 0
            for j in range(i - 1, max(0, i - 100), -1):
                for ch in strip_strings(lines[j]):
                    if ch == '}':
                        depth_back += 1
                    elif ch == '{':
                        depth_back -= 1
                if depth_back < 0:
                    # We've exited the enclosing block
                    break
                if 'final l10n' in lines[j] or 'var l10n' in lines[j]:
                    has_decl = True
                    break
        
        if has_decl:
            i += 1
            continue
        
        # Determine if this is inside a State class
        is_state = False
        for j in range(i - 1, max(0, i - 500), -1):
            cls_stripped = lines[j].strip()
            if re.match(r'class\s+\w+\s+extends\s+State<', cls_stripped):
                is_state = True
                break
            if re.match(r'class\s+\w+', cls_stripped):
                break
        
        # Get indent
        indent_match = re.match(r'^(\s*)', line)
        indent = (indent_match.group(1) if indent_match else '') + '  '
        
        if is_state:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
        else:
            decl = f'{indent}final l10n = context.read<LocalizationProvider>();'
        
        # Insert after the line with {
        lines.insert(i + 1, decl)
        changes += 1
        
        # Don't increment i - check the next line (which is now the old i+1)
        # Actually, skip past the inserted line
        i += 2
    
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
