#!/usr/bin/env python3
"""Enhanced l10n batch replacement - handles multiline Text(), const removal, l10n var injection."""
import re, os

BASE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib'

# Chinese string -> l10n key mapping
STRING_MAP = {
    '搜索结果': 'search_results',
    '搜索知识点...': 'search_topics_hint',
    '高频': 'high_frequency',
    '未配置 AI 模型': 'ai_not_configured',
    '未配置 AI': 'ai_not_config',
    '发布': 'content_published',
    '测试': 'content_testing',
    '草稿': 'content_draft',
    '内容': 'content_label',
    '登录后可查看测试版内容': 'login_for_testing',
    '需要管理员权限查看草稿内容': 'admin_for_draft',
    '语音识别不可用，请检查麦克风权限': 'voice_not_available',
    'Whisper 语音输入暂不支持 Web 端，请使用系统语音': 'voice_web_unsupported',
    '请先在设置中配置 Whisper API': 'voice_no_whisper_key',
    '请授予麦克风权限': 'voice_grant_permission',
    '录音启动失败': 'voice_record_failed',
    '正在识别语音...': 'voice_recognizing',
    '语音识别失败': 'voice_recognize_failed',
    '停止录音': 'voice_stop_recording',
    'Whisper 语音输入': 'voice_whisper_input',
    '语音输入': 'voice_input',
    '请选择一个领域': 'select_domain',
    '搜索当前领域...': 'search_current_domain',
    '隐藏筛选': 'hide_filter',
    '显示筛选': 'show_filter',
    '入门': 'difficulty_easy',
    '基础': 'difficulty_basic',
    '中等': 'difficulty_medium',
    '较难': 'difficulty_hard',
    '困难': 'difficulty_expert',
    '代码题': 'code_problem',
    '排序：': 'sort_label',
    '没有找到匹配的知识点': 'no_matching_topics',
    '个知识点': 'topics_count_suffix',
    '全部': 'all_filter',
    '不熟练': 'filter_not_proficient',
    '未掌握': 'filter_not_mastered',
    '低→高': 'sort_low_to_high',
    '高→低': 'sort_high_to_low',
    '暂无数据': 'no_data',
    '知识查阅': 'knowledge_lookup',
    '面试官关注点': 'interviewer_focus',
    '面试官关注：': 'interviewer_focus_prefix',
    '知识目录': 'knowledge_catalog',
    '前置知识': 'prerequisite_knowledge',
    'LeetCode 练习': 'leetcode_practice',
    '正在加载知识点...': 'practice_loading',
    '选择练习模式': 'select_practice_mode',
    '今日复习': 'today_review',
    '随机抽问': 'random_quiz',
    '追问训练': 'follow_up_training',
    '弱点训练包': 'weakness_training',
    '高频冲刺': 'high_freq_sprint',
    '项目深挖': 'project_deep_dive',
    '系统设计': 'system_design',
    '模拟面试': 'mock_interview_mode',
    '暂无可练习的知识点': 'no_practice_topics',
    '知识点正在加载中，请稍等片刻再试': 'topics_loading_wait',
    '重新加载': 'reload',
    '当前领域没有可追问的知识点': 'no_follow_up_topics',
    '当前领域没有高频知识点': 'no_high_freq_topics',
    '今日复习工作台': 'today_review_workbench',
    '复习负载': 'review_load',
    '暂无待复习内容': 'no_review_content',
    '到期': 'review_due',
    '低分': 'review_low_score',
    '未复习': 'review_unreviewed',
    '退步': 'review_regression',
    '一键开始全部复习': 'start_all_review',
    '今日到期': 'group_due_today',
    '低分优先': 'group_low_score',
    '从未复习': 'group_never_reviewed',
    '掌握度退步': 'group_regressed',
    '今日复习已完成！': 'review_completed',
    '开始复习': 'start_review',
    '推迟': 'defer',
    '已推迟到明天': 'deferred_to_tomorrow',
    '主问': 'primary_question',
    '追问': 'follow_up',
    '澄清': 'clarify',
    '总结': 'interview_summary',
    '已用时': 'elapsed_time',
    '切换场景': 'switch_scenario',
    '没有可用的知识点': 'no_available_topics',
    '知识点加载失败': 'topic_load_failed',
    '下一题': 'next_question',
    '查看面试报告': 'view_report',
    '请先在个人中心配置 AI': 'ai_not_config_profile',
    '请先输入你的回答': 'please_input_answer',
    '综合面试': 'scenario_mixed',
    '基础概念': 'scenario_foundation',
    '算法编程': 'scenario_code',
    '项目实战': 'scenario_project',
    '正式模式': 'formal_mode',
    'AI 评估结果': 'ai_evaluation_result',
    '下一步建议': 'next_action',
    '无追问': 'no_follow_up',
    '面试报告': 'interview_report',
    '面试完成': 'interview_completed',
    '总分': 'total_score',
    '平均分': 'average_score',
    '总题数': 'total_questions_count',
    '总用时': 'total_duration',
    '保存本地练习': 'save_local',
    '重新开始': 'restart',
    'AI 正在分析...': 'ai_analyzing',
    '已添加到回答': 'added_to_answer',
    '添加到回答': 'add_to_answer',
    '系统设计练习': 'system_design_practice',
    '已练习': 'practiced',
    '待练习': 'to_practice',
    '系统设计面试指南': 'system_design_guide',
    '面试流程': 'interview_process',
    '评分维度': 'scoring_dimensions',
    '问题分析能力': 'score_analysis',
    '架构设计能力': 'score_architecture',
    '技术深度': 'score_depth',
    '沟通表达能力': 'score_communication',
    '注意事项': 'notice_title',
    '知道了': 'got_it',
    '开始计时，按步骤完成系统设计': 'start_timer_hint',
    '关闭': 'close',
    '回答版本库': 'answer_versions',
    '添加版本': 'add_version',
    '还没有保存的回答版本': 'no_saved_versions',
    '点击下方按钮添加你的第一版回答': 'click_to_add_first',
    '初稿': 'draft_version',
    'AI 修改版': 'ai_modified_version',
    '面试版': 'interview_version',
    '版本类型': 'version_type',
    '回答内容': 'answer_content',
    '输入你的回答...': 'input_answer_hint',
    '已复制到剪贴板': 'copied_to_clipboard',
    '确认删除': 'confirm_delete',
    '版本已删除': 'version_deleted',
    '版本已保存': 'version_saved',
    '版本已更新': 'version_updated',
    '请先填写回答内容': 'please_input_content',
    'AI 改进建议': 'ai_improvement',
    'AI 正在分析你的回答...': 'ai_analyzing_answer',
    '保存为 AI 修改版': 'save_as_ai_version',
    '已保存为 AI 修改版': 'saved_as_ai_version',
    '设为面试版': 'set_as_interview_version',
    'AI 评估自动保存': 'ai_eval_auto_saved',
    '请输入回答内容': 'input_answer_empty',
    '就绪度': 'readiness',
    '待复习': 'to_review',
    '未复习': 'unreviewed',
    '退步': 'regressed',
    '就绪': 'ready',
    '未掌握': 'not_mastered',
    '通用技术面试准备': 'interview_prep_generic',
    '调整目标': 'adjust_target',
    '设置目标': 'set_target',
    '面试就绪度': 'interview_readiness',
    '今日待复习': 'today_to_review',
    '高频未稳': 'high_freq_unstable',
    '低分回流': 'low_score_reentry',
    '开始今日练习': 'start_today_practice',
    '来一场模拟面试': 'start_mock_interview',
    '隐私与降级': 'privacy_degradation',
    '面试目标': 'interview_goal',
    'JD 匹配分析': 'jd_match_analysis',
    '面试智练': 'app_title',
    '收缩侧边栏': 'collapse_sidebar',
    '展开侧边栏': 'expand_sidebar',
    '学习总时长': 'total_study_time',
    '连续学习': 'streak_days',
    '缓存已清除，正在重新加载当前领域...': 'cache_cleared_reload',
    '从云端恢复': 'restore_from_cloud',
    '确认恢复': 'confirm_restore',
    '取消': 'cancel',
    '确认': 'confirm',
    '保存': 'save',
    '删除': 'delete',
    '编辑': 'edit',
    '返回': 'back',
    '搜索': 'search',
    '登录': 'login',
    '退出': 'logout',
    '重试': 'retry',
    '确定': 'determine',
    '错误': 'error',
    '复制': 'copy',
    '开始练习': 'start_practice_btn',
    '问题': 'question_label',
    '练习': 'practice',
    '学习': 'learn',
    '熟练': 'skilled',
    '开始学习': 'start_learning',
    '掌握度': 'mastery_percent',
}

# Patterns to replace (order matters - longer first)
# We use regex to find 'Chinese text' in various widget contexts
def replace_chinese_in_dart(content, cn, key):
    """Replace Chinese string in various Dart code patterns."""
    replacement = f"l10n.get('{key}')"

    # Escape special regex chars in Chinese text
    escaped = re.escape(cn)

    # Pattern 1: const Text('中文') or const Text("中文") -> Text(l10n.get('key'))
    content = re.sub(
        rf"const\s+Text\(\s*'{escaped}'\s*\)",
        f"Text({replacement})",
        content
    )
    content = re.sub(
        rf'const\s+Text\(\s*"{escaped}"\s*\)',
        f"Text({replacement})",
        content
    )

    # Pattern 2: Text('中文') or Text("中文") -> Text(l10n.get('key'))
    # But NOT if it's already l10n.get(...)
    content = re.sub(
        rf"(?<!l10n\.get\()Text\(\s*'{escaped}'\s*\)",
        f"Text({replacement})",
        content
    )
    content = re.sub(
        rf'(?<!l10n\.get\()Text\(\s*"{escaped}"\s*\)',
        f"Text({replacement})",
        content
    )

    # Pattern 3: Multiline Text with Chinese
    # Text(\n            '中文',\n          )
    content = re.sub(
        rf"(?<!l10n\.get\()Text\(\s*\n\s*'{escaped}'\s*,?\s*\n\s*\)",
        f"Text({replacement})",
        content
    )

    # Pattern 4: hintText: '中文'
    content = re.sub(
        rf"hintText:\s*'{escaped}'",
        f"hintText: {replacement}",
        content
    )

    # Pattern 5: labelText: '中文'
    content = re.sub(
        rf"labelText:\s*'{escaped}'",
        f"labelText: {replacement}",
        content
    )

    # Pattern 6: tooltip: '中文'
    content = re.sub(
        rf"tooltip:\s*'{escaped}'",
        f"tooltip: {replacement}",
        content
    )

    # Pattern 7: title: const Text('中文') -> title: Text(l10n.get('key'))
    content = re.sub(
        rf"title:\s*const\s+Text\(\s*'{escaped}'\s*\)",
        f"title: Text({replacement})",
        content
    )

    # Pattern 8: title: Text('中文')
    content = re.sub(
        rf"title:\s*Text\(\s*'{escaped}'\s*\)",
        f"title: Text({replacement})",
        content
    )

    # Pattern 9: label: const Text('中文') -> label: Text(l10n.get('key'))
    content = re.sub(
        rf"label:\s*const\s+Text\(\s*'{escaped}'\s*\)",
        f"label: Text({replacement})",
        content
    )

    # Pattern 10: label: Text('中文')
    content = re.sub(
        rf"label:\s*Text\(\s*'{escaped}'\s*\)",
        f"label: Text({replacement})",
        content
    )

    # Pattern 11: content: Text('中文') in SnackBar/Dialog
    content = re.sub(
        rf"content:\s*const\s+Text\(\s*'{escaped}'\s*\)",
        f"content: Text({replacement})",
        content
    )
    content = re.sub(
        rf"content:\s*Text\(\s*'{escaped}'\s*\)",
        f"content: Text({replacement})",
        content
    )

    # Pattern 12: child: Text('中文')
    content = re.sub(
        rf"child:\s*const\s+Text\(\s*'{escaped}'\s*\)",
        f"child: Text({replacement})",
        content
    )

    # Pattern 13: String literal in specific contexts like stageLabel map values
    # Only replace in Text() widget contexts, not in data maps

    return content


def add_l10n_import(content):
    """Add localization_provider import."""
    import_line = "import 'package:mianshi_zhilian/providers/localization_provider.dart';"
    if import_line in content:
        return content

    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.strip().startswith("import '") and ('provider' in line or 'mianshi_zhilian' in line):
            insert_idx = i + 1

    lines.insert(insert_idx, import_line)
    return '\n'.join(lines)


def add_l10n_variable(content):
    """Add 'final l10n = context.watch<LocalizationProvider>();' in build methods."""
    if 'context.watch<LocalizationProvider>()' in content:
        return content

    # For StatelessWidget: find build method
    # For StatefulWidget: find build method in State class

    # Pattern: after "final xxx = context.watch<SomeProvider>();" lines
    # Add l10n declaration
    pattern = r"(final \w+ = context\.watch<\w+>\(\);\n)"
    matches = list(re.finditer(pattern, content))
    if matches:
        last_match = matches[-1]
        insert_pos = last_match.end()
        # Check if there's already a l10n line nearby
        nearby = content[insert_pos:insert_pos+200]
        if 'l10n' not in nearby:
            indent = '    '
            content = content[:insert_pos] + indent + "final l10n = context.watch<LocalizationProvider>();\n" + content[insert_pos:]

    return content


def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # Step 1: Add import
    content = add_l10n_import(content)

    # Step 2: Replace Chinese strings
    # Sort by length descending to replace longer strings first
    for cn, key in sorted(STRING_MAP.items(), key=lambda x: -len(x[0])):
        if len(cn) <= 1:
            continue  # Skip single char to avoid false positives
        content = replace_chinese_in_dart(content, cn, key)

    # Step 3: Also handle single-char strings in specific patterns only
    for cn, key in [('取消', 'cancel'), ('确认', 'confirm'), ('保存', 'save'),
                     ('删除', 'delete'), ('编辑', 'edit'), ('返回', 'back'),
                     ('搜索', 'search'), ('登录', 'login'), ('退出', 'logout'),
                     ('重试', 'retry'), ('确定', 'determine'), ('错误', 'error'),
                     ('复制', 'copy'), ('练习', 'practice'), ('学习', 'learn')]:
        content = replace_chinese_in_dart(content, cn, key)

    # Step 4: Add l10n variable in build methods
    if 'l10n.get(' in content and 'context.watch<LocalizationProvider>()' not in content:
        content = add_l10n_variable(content)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False


def main():
    files = [
        os.path.join(BASE, 'widgets/header_bar.dart'),
        os.path.join(BASE, 'widgets/navigation_rail_panel.dart'),
        os.path.join(BASE, 'widgets/voice_input_button.dart'),
        os.path.join(BASE, 'pages/learning/catalog_page.dart'),
        os.path.join(BASE, 'pages/learning/topic_detail_page.dart'),
        os.path.join(BASE, 'pages/practice/practice_page.dart'),
        os.path.join(BASE, 'pages/practice/recall_page.dart'),
        os.path.join(BASE, 'pages/practice/today_review_page.dart'),
        os.path.join(BASE, 'pages/practice/mock_interview_page.dart'),
        os.path.join(BASE, 'pages/practice/system_design_page.dart'),
        os.path.join(BASE, 'pages/practice/answer_versions_page.dart'),
        os.path.join(BASE, 'pages/prep/interview_prep_page.dart'),
        os.path.join(BASE, 'pages/mastery/mastery_page.dart'),
        os.path.join(BASE, 'pages/profile/profile_page.dart'),
        os.path.join(BASE, 'pages/learning/dashboard_page.dart'),
    ]

    for f in files:
        if os.path.exists(f):
            changed = process_file(f)
            count = 0
            with open(f, 'r') as fh:
                count = fh.read().count('l10n.get(')
            print(f"{'✅' if changed else '⏭️'} {os.path.basename(f)} ({count} l10n calls)")
        else:
            print(f"❌ Not found: {f}")


if __name__ == '__main__':
    main()
