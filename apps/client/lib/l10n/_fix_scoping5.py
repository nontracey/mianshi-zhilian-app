#!/usr/bin/env python3
"""v3: Fix l10n scoping using forward brace-depth tracking.
Identifies ALL code blocks at depth 0->1 transitions as function starts."""
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

def strip_strings_and_comments(line):
    """Remove string contents and comments to avoid counting braces inside them."""
    # Remove single-line comments
    result = re.sub(r'//.*$', '', line)
    # Remove string contents (simple approach)
    result = re.sub(r"'[^']*'", "''", result)
    result = re.sub(r'"[^"]*"', '""', result)
    return result

def find_all_blocks(lines):
    """Find all code blocks by tracking brace depth.
    Returns list of (start_line, open_brace_line, close_line, indent, depth)."""
    blocks = []
    depth = 0
    block_starts = []  # Stack of (line_num, indent, depth) for each depth level
    
    for i, line in enumerate(lines):
        stripped = strip_strings_and_comments(line)
        
        for ch in stripped:
            if ch == '{':
                indent_match = re.match(r'^(\s*)', line)
                indent = indent_match.group(1) if indent_match else ''
                block_starts.append((i, indent, depth))
                depth += 1
            elif ch == '}':
                depth -= 1
                if block_starts and block_starts[-1][2] == depth:
                    start_line, indent, _ = block_starts.pop()
                    blocks.append((start_line, start_line, i, indent, depth))
    
    return blocks

def is_state_class(lines, block_start):
    """Check if block_start is inside a State<...> class."""
    for i in range(block_start - 1, max(0, block_start - 500), -1):
        stripped = lines[i].strip()
        if re.match(r'class\s+\w+\s+extends\s+State<', stripped):
            return True
        if re.match(r'class\s+\w+', stripped):
            return False
    return False

def find_class_name(lines, block_start):
    """Find the class name containing this block."""
    for i in range(block_start - 1, max(0, block_start - 500), -1):
        m = re.match(r'class\s+(\w+)', lines[i].strip())
        if m:
            return m.group(1)
    return ''

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
    
    # Step 3: Find all code blocks
    blocks = find_all_blocks(lines)
    
    # Step 4: For each block, check if it contains l10n.get usage
    l10n_line_set = set()
    for i, line in enumerate(lines):
        if 'l10n.get' in line and not line.strip().startswith('//'):
            l10n_line_set.add(i)
    
    # Find blocks that contain l10n.get
    blocks_needing_l10n = []
    for (start, brace, close, indent, block_depth) in blocks:
        has_usage = any(brace <= li <= close for li in l10n_line_set)
        if not has_usage:
            continue
        
        # Skip class declaration blocks - l10n can't be a field initializer
        start_line = lines[start].strip()
        if re.match(r'class\s+\w+', start_line):
            continue
        
        # Skip enum declaration blocks
        if re.match(r'enum\s+\w+', start_line):
            continue
        
        # Skip map/list literal blocks (no function signature on the start line)
        # A function/method block typically has parentheses () before {
        if '(' not in start_line and '{' in start_line:
            # Could be a map literal, set literal, or cascade
            # Skip unless it looks like a function
            if not re.search(r'\w+\s*\(', start_line):
                continue
        
        # Check if l10n is already declared in first 10 lines
        has_decl = False
        for j in range(brace, min(brace + 10, close + 1)):
            if j < len(lines) and ('final l10n' in lines[j] or 'var l10n' in lines[j] or 'late final l10n' in lines[j]):
                has_decl = True
                break
        
        if not has_decl:
            is_state = is_state_class(lines, start)
            blocks_needing_l10n.append((brace, indent + '  ', is_state))
    
    # Insert declarations from bottom to top
    blocks_needing_l10n.sort(key=lambda x: x[0], reverse=True)
    for (brace_line, indent, is_state) in blocks_needing_l10n:
        if is_state:
            decl = f'{indent}final l10n = context.watch<LocalizationProvider>();'
        else:
            decl = f'{indent}final l10n = context.read<LocalizationProvider>();'
        lines.insert(brace_line + 1, decl)
        changes += 1
    
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
