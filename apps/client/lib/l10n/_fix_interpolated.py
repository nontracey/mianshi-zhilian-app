#!/usr/bin/env python3
"""Replace interpolated Chinese strings with l10n.getp() calls.

Handles patterns like:
  '已将「${topic.title}」推迟到明天'  →  l10n.getp('已将「{title}」推迟到明天', {'title': topic.title})
  '已逾期 $daysOverdue 天'           →  l10n.getp('已逾期 {daysOverdue} 天', {'daysOverdue': daysOverdue})
  '${_searchResults.length} 项'       →  l10n.getp('{count} 项', {'count': _searchResults.length})
"""
import re
import sys
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Files to process
TARGET_FILES = [
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
    'main.dart',
]

# Strings to skip (data matching, AI prompts, comments)
SKIP_PATTERNS = [
    r'\.contains\(',      # Data matching
    r'\.startsWith\(',    # Data matching
    r'// ',               # Comments
    r'contextParts\.add', # AI prompt building
    r'contextualAnswer',  # AI prompt building
    r'\[追问回答\]',       # AI prompt
    r'\[澄清回答\]',       # AI prompt
]

def is_skip_line(line):
    for pat in SKIP_PATTERNS:
        if re.search(pat, line):
            return True
    return False

def extract_interpolation_vars(s):
    """Extract variables from Dart string interpolation like '${var}' or '$var'."""
    vars = []
    # Match ${...} (complex expressions)
    for m in re.finditer(r'\$\{([^}]+)\}', s):
        expr = m.group(1)
        # Generate a param name from the expression
        # e.g., topic.title → title, _searchResults.length → count
        if '.' in expr:
            param_name = expr.split('.')[-1]
        elif expr.startswith('_'):
            param_name = expr.lstrip('_')
        else:
            param_name = expr
        # Clean up
        param_name = re.sub(r'[^a-zA-Z0-9]', '_', param_name).strip('_')
        if not param_name:
            param_name = 'param'
        vars.append((m.group(0), param_name, expr))
    # Match $var (simple variable)
    for m in re.finditer(r'\$([a-zA-Z_][a-zA-Z0-9_]*)', s):
        # Skip if already matched as ${...}
        if s[m.start()-1:m.start()+1] == '${':
            continue
        var = m.group(1)
        vars.append((m.group(0), var, var))
    return vars

def process_string_literal(s):
    """Convert a Dart string with interpolation to l10n.getp() call.
    Returns (new_string, params_dict) or None if no interpolation."""
    vars = extract_interpolation_vars(s)
    if not vars:
        return None
    
    # Build the key by replacing $var/${expr} with {param_name}
    key = s
    params = []
    seen_params = set()
    for original, param_name, expr in vars:
        # Deduplicate param names
        base = param_name
        i = 2
        while param_name in seen_params:
            param_name = f"{base}{i}"
            i += 1
        seen_params.add(param_name)
        key = key.replace(original, '{' + param_name + '}', 1)
        params.append((param_name, expr))
    
    # Build params map string
    params_map = ', '.join(f"'{p}': {e}" for p, e in params)
    
    return key, params_map

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    changes = 0
    new_keys = []
    
    lines = content.split('\n')
    new_lines = []
    
    for i, line in enumerate(lines):
        if is_skip_line(line):
            new_lines.append(line)
            continue
        
        # Find interpolated Chinese strings
        # Match single-quoted strings with $ that contain Chinese
        # Pattern: '...${...}...' or '...$var...' where the string contains Chinese
        def replace_interp_string(m):
            nonlocal changes
            full = m.group(0)
            inner = m.group(1)
            
            # Check if it contains Chinese
            if not re.search(r'[\u4e00-\u9fff]', inner):
                return full
            
            # Check if it has interpolation
            if '$' not in inner:
                return full
            
            # Skip if already wrapped in l10n
            if 'l10n.get' in full:
                return full
            
            result = process_string_literal(inner)
            if result is None:
                return full
            
            key, params_map = result
            new_keys.append(key)
            changes += 1
            return f"l10n.getp('{key}', {{{params_map}}})"
        
        # Match single-quoted strings
        new_line = re.sub(r"'((?:[^'\\]|\\.)*?)'", replace_interp_string, line)
        
        # Also match double-quoted strings
        new_line = re.sub(r'"((?:[^"\\]|\\.)*?)"', replace_interp_string, new_line)
        
        new_lines.append(new_line)
    
    content = '\n'.join(new_lines)
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"  Modified: {os.path.relpath(filepath, BASE)} ({changes} changes)")
    
    return changes, new_keys

def main():
    total_changes = 0
    all_keys = set()
    
    for rel_path in TARGET_FILES:
        filepath = os.path.join(BASE, rel_path)
        if not os.path.exists(filepath):
            print(f"  SKIP (not found): {rel_path}")
            continue
        
        changes, new_keys = process_file(filepath)
        total_changes += changes
        all_keys.update(new_keys)
    
    print(f"\nTotal changes: {total_changes}")
    print(f"New keys needed: {len(all_keys)}")
    
    # Print keys for adding to l10n.dart
    if all_keys:
        print("\n--- Keys to add to l10n.dart ---")
        for key in sorted(all_keys):
            # Generate English translation (simple heuristic)
            en = key
            # Replace Chinese patterns
            en = re.sub(r'已将「\{(\w+)\}」推迟到明天', r'Postponed {\1} to tomorrow', en)
            en = re.sub(r'已将「\{(\w+)\}」推迟', r'Postponed {\1}', en)
            en = re.sub(r'已逾期 \{(\w+)\} 天，遗忘风险极高', r'{\1} days overdue, high forgetting risk', en)
            en = re.sub(r'已逾期 \{(\w+)\} 天，遗忘风险增加', r'{\1} days overdue, increased forgetting risk', en)
            en = re.sub(r'距上次练习 \{(\w+)\} 天，按遗忘曲线到期', r'{\1} days since last practice, due by forgetting curve', en)
            en = re.sub(r'提前复习（原定 \{(\w+)\} 天后）', r'Early review (originally due in {\1} days)', en)
            en = re.sub(r'共 \{(\w+)\} 个知识点等待复习', r'{\1} topics waiting for review', en)
            en = re.sub(r'请用自己的话解释 \{(\w+)\} 的核心内容。', r'Explain the core content of {\1} in your own words.', en)
            en = re.sub(r'请解释 \{(\w+)\} 的核心概念', r'Explain the core concept of {\1}', en)
            en = re.sub(r'面试官关注：\{(\w+)\}', r'Interviewer focus: {\1}', en)
            en = re.sub(r'基于遗忘曲线，今天有 \{(\w+)\} 个知识点待复习', r'Based on forgetting curve, {\1} topics to review today', en)
            en = re.sub(r'连续学习 \{(\w+)\} 天', r'{\1} day streak', en)
            en = re.sub(r'AI 评估失败：\{(\w+)\}', r'AI evaluation failed: {\1}', en)
            en = re.sub(r'AI 改进失败: \{(\w+)\}', r'AI improvement failed: {\1}', en)
            en = re.sub(r'选择图片失败: \{(\w+)\}', r'Image selection failed: {\1}', en)
            en = re.sub(r'拍照失败: \{(\w+)\}', r'Photo capture failed: {\1}', en)
            en = re.sub(r'流式输出失败：\{(\w+)\}', r'Streaming output failed: {\1}', en)
            en = re.sub(r'评估失败：\{(\w+)\}', r'Evaluation failed: {\1}', en)
            en = re.sub(r'发现新版本 v\{(\w+)\}', r'New version v{\1} available', en)
            en = re.sub(r'发布日期：\{(\w+)\}', r'Release date: {\1}', en)
            en = re.sub(r'正在下载 v\{(\w+)\}\.\.\.', r'Downloading v{\1}...', en)
            en = re.sub(r'v\{(\w+)\} 下载完成', r'v{\1} download complete', en)
            en = re.sub(r'\{(\w+)\} 功能待开通', r'{\1} feature coming soon', en)
            en = re.sub(r'\{(\w+)\} 功能待开通，可先使用本地数据和 WebDAV 备份', r'{\1} feature coming soon, use local data and WebDAV backup for now', en)
            en = re.sub(r'练习：\{(\w+)\}', r'Practice: {\1}', en)
            en = re.sub(r'技术栈：\{(\w+)\}', r'Tech stack: {\1}', en)
            en = re.sub(r'每日 \{(\w+)\} 分钟', r'{\1} min/day', en)
            en = re.sub(r'每日投入 \{(\w+)\} 分钟', r'{\1} min/day investment', en)
            en = re.sub(r'当前方式：\{(\w+)\}', r'Current method: {\1}', en)
            en = re.sub(r'第 \{(\w+)\} / \{(\w+)\} 题', r'Question {\1} of {\2}', en)
            en = re.sub(r'第 \{(\w+)\} 轮', r'Round {\1}', en)
            en = re.sub(r'问题 \{(\w+)\}', r'Question {\1}', en)
            en = re.sub(r'追问记录（\{(\w+)\} 轮）', r'Follow-up history ({\1} rounds)', en)
            en = re.sub(r'本题用时 \{(\w+)\}', r'Time spent: {\1}', en)
            en = re.sub(r'用时 \{(\w+)\}', r'Time: {\1}', en)
            en = re.sub(r'匹配 \{(\w+)\} / \{(\w+)\} 题', r'Matched {\1} / {\2} questions', en)
            en = re.sub(r'\{(\w+)\} 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。', r'{\1} questions scored below 60, review weak topics before next mock interview.', en)
            en = re.sub(r'最近得分 \{(\w+)\} 分（已练习 \{(\w+)\} 次），需要重新组织回答', r'Last score: {\1} (practiced {\2} times), needs answer reorganization', en)
            en = re.sub(r'高频知识点，当前 \{(\w+)\} 分，未达熟练阈值', r'High-frequency topic, current {\1} points, below proficiency threshold', en)
            en = re.sub(r'距上次练习已 \{(\w+)\} 天，建议尽快复习巩固', r'{\1} days since last practice, review recommended soon', en)
            en = re.sub(r'从 \{(\w+)\} 分降至 \{(\w+)\} 分（下降 \{(\w+)\} 分）', r'Dropped from {\1} to {\2} ({\3} points decrease)', en)
            en = re.sub(r'面试日期：\{(\w+)\}', r'Interview date: {\1}', en)
            en = re.sub(r'\{(\w+)\} 项匹配', r'{\1} matches', en)
            en = re.sub(r'\{(\w+)\} 项', r'{\1} items', en)
            en = re.sub(r'\{(\w+)\} 题', r'{\1} questions', en)
            en = re.sub(r'\{(\w+)\} 个知识点', r'{\1} topics', en)
            en = re.sub(r'\{(\w+)\} 考点', r'{\1} topics', en)
            en = re.sub(r'\{(\w+)\} 练习', r'{\1} practices', en)
            en = re.sub(r'\{(\w+)\} 分', r'{\1} points', en)
            en = re.sub(r'\{(\w+)\} 字', r'{\1} characters', en)
            en = re.sub(r'\{(\w+)\} 天', r'{\1} days', en)
            en = re.sub(r'\{(\w+)\} 分钟', r'{\1} min', en)
            en = re.sub(r'\{(\w+)\} 分钟前', r'{\1} min ago', en)
            en = re.sub(r'\{(\w+)\} 小时前', r'{\1} hours ago', en)
            en = re.sub(r'\{(\w+)\} 天前', r'{\1} days ago', en)
            en = re.sub(r'\{(\w+)\} 分钟后', r'{\1} min later', en)
            en = re.sub(r'\{(\w+)\} 小时后', r'{\1} hours later', en)
            en = re.sub(r'\{(\w+)\} 天后', r'{\1} days later', en)
            en = re.sub(r'进度 \{(\w+)\}%', r'Progress {\1}%', en)
            en = re.sub(r'考点 \{(\w+)\}', r'Topics {\1}', en)
            en = re.sub(r'当前：\{(\w+)\}', r'Current: {\1}', en)
            en = re.sub(r'默认：\{(\w+)\}', r'Default: {\1}', en)
            en = re.sub(r'平台：\{(\w+)\}', r'Platform: {\1}', en)
            en = re.sub(r'原始回答：\\n\{(\w+)\}', r'Original answer:\\n{\1}', en)
            en = re.sub(r'请帮我改进以下面试回答：\\n\\n\{(\w+)\}', r'Please help improve this interview answer:\\n\\n{\1}', en)
            # Time patterns
            en = re.sub(r'今天 \{(\w+)\}', r'Today {\1}', en)
            en = re.sub(r'明天 \{(\w+)\}', r'Tomorrow {\1}', en)
            # Simple substitutions
            en = en.replace('：', ': ')
            en = en.replace('「', '"')
            en = en.replace('」', '"')
            en = en.replace('，', ', ')
            en = en.replace('。', '.')
            en = en.replace('、', ', ')
            
            print(f"    '{key}': '{en}',")
    
    return 0 if total_changes > 0 else 1

if __name__ == '__main__':
    sys.exit(main())
