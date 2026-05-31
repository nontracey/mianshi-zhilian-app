#!/usr/bin/env python3
"""Replace auto-generated English placeholders and Chinese values in _en section."""
import re

FILE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib/l10n/l10n.dart'

# Mapping of key -> proper English translation (plain Python strings, no Dart escaping)
# The to_file_value() function handles escaping for the Dart file format
TRANSLATIONS = {
    'about': 'About Interview Coach',
    'account': 'Account',
    'actual_case': 'Real-World Example',
    'add_config': 'Add Configuration',
    'add_new_config': 'Add New Configuration',
    'add_project': 'Add Project',
    'answer_draft': 'Answer Draft',
    'answer_template': 'Answer Template',
    'appearance': 'Appearance & Theme',
    'bonus_items': 'Bonus Items',
    'capability': 'Capabilities',
    'change_password': 'Change Password',
    'check_update': 'Check for Updates',
    'clear_failed': 'Clear Failed',
    'clear_local_data': 'Clear Local Data',
    'clear_today_review': "Clear Today's Review",
    'common_mistakes': 'Common Mistakes',
    'complete': 'Complete',
    'confirm_before_upload': 'Confirm Before Upload',
    'confirm_clear': 'Confirm Clearing',
    'confirm_new_password': 'Confirm New Password',
    'confirm_password': 'Confirm Password',
    'confirm_upload': 'Confirm Upload',
    'continue_learning': 'Continue Learning',
    'create_new_account': 'Create New Account',
    'current_password': 'Current Password',
    'data_cleared': 'Data Cleared',
    'data_management': 'Data Management',
    'data_upload_confirmation': 'Data Upload Confirmation',
    'deep_dig_practice': 'Deep-Dive Practice',
    'detailed_description': 'Detailed Description',
    'edit_config': 'Edit Configuration',
    'edit_route': 'Edit Route',
    'enable': 'Enable',
    'export_failed': 'Export Failed',
    'export_local_data': 'Export Local Data',
    'high': 'High',
    'hint': 'Hint',
    'image_attachment': 'Image Attachment',
    'image_understanding': 'Image Understanding',
    'install': 'Install',
    'interviewer_focus': "Interviewer's Focus",
    'job_description': 'Job Description',
    'learning_mode': 'Learning Mode',
    'learning_rhythm': 'Learning Rhythm',
    'learning_settings': 'Learning Settings',
    'login_account': 'Login Account',
    'main_question': 'Main Question',
    'manual_sync': 'Manual Sync',
    'medium': 'Medium',
    'missed_points': 'Missed Points',
    'model_capability_statement': 'Model Capability Statement',
    'model_name': 'Model Name',
    'modification_failed': 'Modification Failed',
    'must_cover': 'Key Points to Cover',
    'must_include': 'Must Include',
    'name': 'Name',
    'new_password': 'New Password',
    'nickname': 'Nickname',
    'optimized_answer': 'Optimized Answer',
    'optional_domains': 'Optional Domains',
    'password': 'Password',
    'practice': 'Practice',
    'privacy_protection': 'Privacy Protection',
    'privacy_protection_commitment': 'Privacy Protection Commitment',
    'privacy_settings': 'Privacy Settings',
    'project_deep_dig_library': 'Project Deep-Dive Library',
    'recall_question': 'Recall Question',
    'recall_scoring': 'Recall Scoring',
    'recent_practice': 'Recent Practice',
    'reference_answer': 'Reference Answer',
    'register': 'Register',
    'register_account': 'Register Account',
    'reset_password_ticket': 'Reset Password Ticket',
    'route_name': 'Route Name',
    'save_locally': 'Save Locally',
    'save_route': 'Save Route',
    'scoring_criteria': 'Scoring Criteria',
    'start_recall': 'Start Recall',
    'start_today_practice': "Start Today's Practice",
    'start_training': 'Start Training',
    'status': 'Status',
    'subject': 'Subject',
    'submit_failed': 'Submit Failed',
    'submit_feedback': 'Submit Feedback',
    'submit_ticket': 'Submit Ticket',
    'sync_now': 'Sync Now',
    'template_usage_guide': 'Template Usage Guide',
    'text_ea189e1f': 'After evaluation: if the answer is already sufficient, return an overall assessment; if further clarification is needed, include a "followUp" field in the JSON with follow-up questions. Maximum 2 rounds of follow-up.',
    'today_review': "Today's Review",
    'today_review_queue': "Today's Review Queue",
    'total_mastery': 'Total Mastery',
    'total_weaknesses': 'Total Weak Spots',
    'update_content': 'Update Content',
    'update_now': 'Update Now',
    'upload_confirmation': 'Upload Confirmation',
    'usage_purpose': 'Purpose',
    'usage_tag': 'Usage Tag',
    'use_this_template': 'Use This Template',
    'username': 'Username',
    'verification_code_reset': 'Verification Code Reset',
    'voice_recording': 'Voice Recording',
    'your_answer': 'Your Answer',
    # Chinese-valued entries in _en (4 entries)
    '你是一位资深面试辅导专家_擅长帮助候选人优化面试回答': (
        'You are an experienced interview coaching expert, skilled at helping '
        'candidates optimize their interview responses.'
    ),
    '只输出改进后的回答内容_不要加前缀说明_nn': (
        'Only output the improved answer content. '
        'Do not add any prefix explanations.\n\n'
    ),
    '请帮我改进以下面试回答_使其更结构化_更专业_更完整': (
        'Please help me improve the following interview answers to make them '
        'more structured, professional, and complete.'
    ),
    '请给出最终综合评估_不再追问': (
        'Please provide a final comprehensive evaluation without further '
        'follow-up questions.'
    ),
}


def to_dart_value(s: str) -> str:
    """Convert a plain Python string to the Dart file representation.
    
    - ' -> \\'  (escaped single quote in Dart single-quoted string)
    - \\ -> \\\\ (escaped backslash in Dart)
    - newline -> \\n (newline escape in Dart)
    """
    result = []
    for c in s:
        if c == "'":
            result.append("\\'")  # Dart single-quote escape
        elif c == '\\':
            result.append('\\\\')  # Dart backslash escape
        elif c == '\n':
            result.append('\\n')  # Dart newline escape
        else:
            result.append(c)
    return ''.join(result)


with open(FILE) as f:
    lines = f.readlines()

# Find line where _en section starts
en_start_line = None
for i, line in enumerate(lines):
    if "static const _en = {" in line:
        en_start_line = i
        break

if en_start_line is None:
    print('ERROR: Could not find _en section')
    exit(1)

print(f'_en section starts at line {en_start_line}')

# Pattern for key-value pairs
pat = re.compile(r"^\s+'([^']+)':\s+'((?:[^'\\\\]|\\.)*)'\s*,?$")

changes = 0
for i in range(en_start_line, len(lines)):
    line = lines[i]
    m = pat.match(line)
    if m:
        key = m.group(1)
        if key in TRANSLATIONS:
            new_val = to_dart_value(TRANSLATIONS[key])
            indent = line[:len(line) - len(line.lstrip())]
            trailing = ',' if line.rstrip().endswith(',') else ''
            new_line = f"{indent}'{key}': '{new_val}',{trailing}\n"
            if line != new_line:
                lines[i] = new_line
                changes += 1
                if changes <= 3 or key == 'text_ea189e1f':
                    print(f'  Changed: {key}')

if changes == 0:
    print('ERROR: No changes were made')
    exit(1)

with open(FILE, 'w') as f:
    f.writelines(lines)

print(f'\nUpdated {changes} translation entries in _en section')
