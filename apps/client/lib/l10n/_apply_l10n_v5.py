#!/usr/bin/env python3
"""v5: Handle remaining complex patterns after v4.
Targets: ternary in params, string interpolation, map values, const Text with style, function call args."""
import re, os

BASE = '/Users/yingjunchi/code/mianshi-zhilian-app/apps/client/lib'

# Subset of keys needed for v5 patterns (only the ones v4 missed)
EXTRA_MAP = {
    '隐藏筛选': 'hide_filter',
    '显示筛选': 'show_filter',
    '清除': 'clear_filter',
    '清除筛选': 'clear_all_filters',
    '默认': 'sort_default',
    '难度': 'sort_difficulty',
    '分数': 'sort_score',
    '复习时间': 'sort_review_time',
    '入门': 'difficulty_easy',
    '基础': 'difficulty_basic',
    '中等': 'difficulty_medium',
    '较难': 'difficulty_hard',
    '困难': 'difficulty_expert',
    '熟练': 'skilled',
    '不熟练': 'filter_not_proficient',
    '未掌握': 'filter_not_mastered',
    '熟悉': 'familiar',
    '不熟悉': 'unfamiliar',
    '未学习': 'unlearned',
    '选择领域': 'select_domain',
    '个知识点': 'topics_count_suffix',
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
    '基于遗忘曲线，今天有': 'subtitle_daily_review_prefix',
    '个知识点待复习': 'subtitle_daily_review_suffix',
    '选择领域后随机抽取知识点进行复述练习': 'subtitle_random_quiz',
    '模拟面试官追问，深入练习知识点': 'subtitle_follow_up',
    '针对薄弱知识点进行专项训练': 'subtitle_weakness',
    '针对高频面试题进行强化训练': 'subtitle_high_freq',
    'STAR法则练习，深入项目细节': 'subtitle_project',
    '系统设计面试练习': 'subtitle_system_design',
    '连续多题模式，模拟真实面试场景': 'subtitle_mock_interview',
    '复习已到期的知识点': 'subtitle_daily_review',
    '练习模式': 'practice_mode',
    '选择练习模式': 'select_practice_mode',
    '正在加载知识点...': 'practice_loading',
    '账户管理': 'account_settings',
    '修改资料': 'edit_profile',
    '练习记录': 'practice_records',
    '连续天数': 'streak_days_count',
    '同步方式': 'sync_method',
    '邮箱已绑定': 'email_bound',
    '绑定邮箱': 'bind_email',
    '已绑定': 'bound',
    '待开通': 'coming_soon',
    '微信已绑定': 'wechat_bound',
    '绑定微信': 'bind_wechat',
    '绑定其他账号': 'bind_other',
    '第三方账号绑定': 'third_party_bind',
    '更换头像': 'change_avatar',
    '本地游客模式': 'local_guest_mode',
    '数据保存在本机': 'data_saved_locally',
    '本地游客模式 · 数据保存在本机': 'local_guest_mode_hint',
    '不登录也可以完整学习和练习。登录只用于云端备份和跨设备恢复，登录后会提示合并本地数据。': 'privacy_no_login_hint',
    '确定要退出登录吗？': 'confirm_logout',
    '到期': 'review_due',
    '低分': 'review_low_score',
    '未复习': 'unreviewed',
    '退步': 'regressed',
    '面试准备': 'interview_prep',
    '复述': 'recall',
    '评估': 'evaluation',
    '回答': 'answer',
    '提交': 'submit',
    '跳过': 'skip',
    '完成': 'done',
    '设置': 'settings',
    '暂无回答': 'no_answer_yet',
    '参考回答': 'reference_answer',
    '关键点': 'key_points',
    '建议': 'suggestions',
    '评分': 'score_label',
    'AI 改进': 'ai_improve',
    '添加回答版本': 'add_answer_version_title',
    '编辑版本': 'edit_version_title',
    '已设为面试版': 'set_as_interview_version_done',
    '搜索知识点...': 'search_topics_hint',
    '搜索当前领域...': 'search_current_domain',
    '面试智练': 'app_title',
    '学习': 'nav_learning',
    '知识': 'nav_catalog',
    '练习': 'nav_practice',
    '掌握': 'nav_mastery',
    '我的': 'nav_profile',
    '目录': 'section_catalog',
    '面试': 'section_prep',
    '掌握度': 'mastery_percent',
    '收缩侧边栏': 'collapse_sidebar',
    '展开侧边栏': 'expand_sidebar',
    '学习总时长': 'total_study_time',
    '连续学习': 'streak_days',
    '语音输入': 'voice_input',
    '知识查阅': 'knowledge_lookup',
    '知识目录': 'knowledge_catalog',
    '前置知识': 'prerequisite_knowledge',
    'LeetCode 练习': 'leetcode_practice',
    '面试官关注点': 'interviewer_focus',
    '面试官关注：': 'interviewer_focus_prefix',
    '就绪度': 'readiness',
    '待复习': 'to_review',
    '未复习': 'unreviewed',
    '就绪': 'ready',
    '高频': 'high_frequency',
    '全部': 'all_filter',
    '不熟练': 'filter_not_proficient',
    '低→高': 'sort_low_to_high',
    '高→低': 'sort_high_to_low',
    '暂无数据': 'no_data',
    '开始复习': 'start_review',
    '推迟': 'defer',
    '下一题': 'next_question',
    '开始练习': 'start_practice_btn',
    '问题': 'question_label',
    '内容': 'content_label',
    '发布': 'content_published',
    '测试': 'content_testing',
    '草稿': 'content_draft',
    '搜索': 'search',
    '登录': 'login',
    '退出': 'logout',
    '取消': 'cancel',
    '确认': 'confirm',
    '保存': 'save',
    '删除': 'delete',
    '编辑': 'edit',
    '返回': 'back',
    '重试': 'retry',
    '确定': 'determine',
    '错误': 'error',
    '复制': 'copy',
    '练习': 'practice',
    '学习': 'learn',
    '熟练': 'skilled',
    '代码题': 'code_problem',
    '排序：': 'sort_label',
    '搜索结果': 'search_results',
    '隐私与降级': 'privacy_degradation',
    '调整目标': 'adjust_target',
    '设置目标': 'set_target',
    '高频未稳': 'high_freq_unstable',
    '低分回流': 'low_score_reentry',
    '今日待复习': 'today_to_review',
    '开始今日练习': 'start_today_practice',
    '下一步建议': 'next_step_suggestions',
    '已复制到剪贴板': 'copied_to_clipboard',
    '添加到回答': 'add_to_answer',
    '重新开始': 'restart',
    '切换场景': 'switch_scenario',
    '正式模式': 'formal_mode',
    '综合面试': 'scenario_mixed',
    '基础概念': 'scenario_foundation',
    '算法编程': 'scenario_code',
    '项目实战': 'scenario_project',
    '已用时': 'elapsed_time',
    '总分': 'total_score',
    '平均分': 'average_score',
    '总用时': 'total_duration',
    '主问': 'primary_question',
    '澄清': 'clarify',
    '总结': 'interview_summary',
    '无追问': 'no_follow_up',
    '确认删除': 'confirm_delete',
    '版本已删除': 'version_deleted',
    '版本已保存': 'version_saved',
    '版本已更新': 'version_updated',
    '版本类型': 'version_type',
    '回答内容': 'answer_content',
    '输入你的回答...': 'input_answer_hint',
    '请输入回答内容': 'input_answer_empty',
    '添加版本': 'add_version',
    'AI 修改版': 'ai_modified_version',
    '面试版': 'interview_version',
    'AI 正在分析...': 'ai_analyzing',
    '从云端恢复': 'restore_from_cloud',
    '确认恢复': 'confirm_restore',
    '复习负载': 'review_load',
    '今日到期': 'group_due_today',
    '低分优先': 'group_low_score',
    '从未复习': 'group_never_reviewed',
    '掌握度退步': 'group_regressed',
    '评分维度': 'scoring_dimensions',
    '问题分析能力': 'score_analysis',
    '架构设计能力': 'score_architecture',
    '沟通表达能力': 'score_communication',
    '注意事项': 'notice_title',
    '系统设计练习': 'system_design_practice',
    '已练习': 'practiced',
    '待练习': 'to_practice',
    '技术深度': 'score_depth',
    '知道了': 'got_it',
    '关闭': 'close',
    '初稿': 'draft_version',
    '面试报告': 'interview_report',
    '面试完成': 'interview_completed',
    '总题数': 'total_questions_count',
    '保存本地练习': 'save_local',
    'AI 评估结果': 'ai_evaluation_result',
    '请先在个人中心配置 AI': 'ai_not_config_profile',
    '请先输入你的回答': 'please_input_answer',
    '查看面试报告': 'view_report',
    '没有可用的知识点': 'no_available_topics',
    '知识点加载失败': 'topic_load_failed',
    '已添加到回答': 'added_to_answer',
    'AI 正在分析你的回答...': 'ai_analyzing_answer',
    '回答版本库': 'answer_versions',
    '还没有保存的回答版本': 'no_saved_versions',
    '点击下方按钮添加你的第一版回答': 'click_to_add_first',
    'AI 改进建议': 'ai_improvement',
    '请先填写回答内容': 'please_input_content',
    '保存为 AI 修改版': 'save_as_ai_version',
    '已保存为 AI 修改版': 'saved_as_ai_version',
    '设为面试版': 'set_as_interview_version',
    'AI 评估自动保存': 'ai_eval_auto_saved',
    '面试就绪度': 'interview_readiness',
    '来一场模拟面试': 'start_mock_interview',
    '面试目标': 'interview_goal',
    'JD 匹配分析': 'jd_match_analysis',
    '通用技术面试准备': 'interview_prep_generic',
    '未配置 AI 模型': 'ai_not_configured',
    '未配置 AI': 'ai_not_config',
    '正在识别语音...': 'voice_recognizing',
    '语音识别失败': 'voice_recognize_failed',
    '请授予麦克风权限': 'voice_grant_permission',
    '录音启动失败': 'voice_record_failed',
    '停止录音': 'voice_stop_recording',
    'Whisper 语音输入': 'voice_whisper_input',
    '没有找到匹配的知识点': 'no_matching_topics',
    '系统设计面试指南': 'system_design_guide',
    '面试流程': 'interview_process',
    '开始计时，按步骤完成系统设计': 'start_timer_hint',
    '一键开始全部复习': 'start_all_review',
    '今日复习已完成！': 'review_completed',
    '今日复习工作台': 'today_review_workbench',
    '暂无待复习内容': 'no_review_content',
    '已将知识点推迟到明天': 'deferred_to_tomorrow',
    '切换场景将重新开始面试，当前进度会丢失。确定切换吗？': 'switch_scenario_confirm',
    '确定要删除这个版本吗？': 'confirm_delete_version',
    '缓存已清除，正在重新加载当前领域...': 'cache_cleared_reload',
    '恢复将覆盖当前所有本地数据，此操作不可撤销。是否继续？': 'restore_confirm_msg',
    'Whisper 语音输入暂不支持 Web 端，请使用系统语音': 'voice_web_unsupported',
    '语音识别不可用，请检查麦克风权限': 'voice_not_available',
    '请先在设置中配置 Whisper API': 'voice_no_whisper_key',
    '未配置 AI，已复制到剪贴板，可粘贴到外部 AI 对话': 'ai_not_config_copy',
    '当前领域没有可追问的知识点': 'no_follow_up_topics',
    '当前领域没有高频知识点': 'no_high_freq_topics',
    '知识点正在加载失败': 'topic_load_failed',
    '需要管理员权限查看草稿内容': 'admin_for_draft',
    '登录后可查看测试版内容': 'login_for_testing',
    '优先冲刺高频未稳知识点，适合临近面试。': 'action_high_freq_sprint',
    '先清今日复习，避免到期内容继续遗忘。': 'action_clear_review',
    '就绪度偏低，建议先低分回流，再做模拟面试。': 'action_low_readiness',
    '可以进入正式模拟模式，结束后统一复盘。': 'action_ready_for_mock',
    '设置目标岗位或粘贴 JD 后，可获得更贴近岗位的准备建议。': 'action_set_target',
    '未设置目标岗位也可以直接使用。当前按通用技术面试路径推荐复习、高频题和模拟面试。': 'no_target_hint',
    '目标已设置，App 会增强推荐权重。': 'target_set_hint',
    '目标岗位、JD、项目素材和回答草稿默认只保存在本地。': 'privacy_local_save',
    '不登录也能完整练习；登录只用于云端备份和跨设备恢复。': 'privacy_no_login',
    '未配置 AI 模型时，练习会降级为本地作答、自评和参考回答。': 'privacy_ai_fallback',
    '未识别到关键技术词，请检查 JD 内容。': 'jd_no_keywords',
    '当前内容库中未找到与 JD 匹配的知识点。': 'jd_no_match',
    '建议优先复习（按掌握度从低到高）：': 'jd_suggest_review',
    '保存你的多版回答，支持"初稿 -> AI 修改 -> 面试版"迭代': 'version_iteration_hint',
    '选择领域后随机抽取知识点进行复述练习': 'subtitle_random_quiz',
    '模拟面试官追问，深入练习知识点': 'subtitle_follow_up',
    '针对薄弱知识点进行专项训练': 'subtitle_weakness',
    '针对高频面试题进行强化训练': 'subtitle_high_freq',
    'STAR法则练习，深入项目细节': 'subtitle_project',
    '系统设计面试练习': 'subtitle_system_design',
    '连续多题模式，模拟真实面试场景': 'subtitle_mock_interview',
    '复习已到期的知识点': 'subtitle_daily_review',
    '面试官关注：': 'interviewer_focus_prefix',
    '追问训练': 'follow_up_training',
    '弱点训练包': 'weakness_training',
    '高频冲刺': 'high_freq_sprint',
    '项目深挖': 'project_deep_dive',
    '模拟面试': 'mock_interview_mode',
    '今日复习': 'today_review',
    '随机抽问': 'random_quiz',
    '请选择一个领域': 'select_domain',
    '搜索当前领域...': 'search_current_domain',
    '正在加载知识点...': 'practice_loading',
    '选择练习模式': 'select_practice_mode',
    '暂无可练习的知识点': 'no_practice_topics',
    '请先在个人中心配置 AI': 'ai_not_config_profile',
    '请先输入你的回答': 'please_input_answer',
    '没有可用的知识点': 'no_available_topics',
    '知识点加载失败': 'topic_load_failed',
    '已添加到回答': 'added_to_answer',
    'AI 正在分析你的回答...': 'ai_analyzing_answer',
    '回答版本库': 'answer_versions',
    '还没有保存的回答版本': 'no_saved_versions',
    '点击下方按钮添加你的第一版回答': 'click_to_add_first',
    'AI 改进建议': 'ai_improvement',
    '请先填写回答内容': 'please_input_content',
    '保存为 AI 修改版': 'save_as_ai_version',
    '已保存为 AI 修改版': 'saved_as_ai_version',
    '设为面试版': 'set_as_interview_version',
    'AI 评估自动保存': 'ai_eval_auto_saved',
    '面试就绪度': 'interview_readiness',
    '来一场模拟面试': 'start_mock_interview',
    '面试目标': 'interview_goal',
    'JD 匹配分析': 'jd_match_analysis',
    '通用技术面试准备': 'interview_prep_generic',
    '未配置 AI 模型': 'ai_not_configured',
    '未配置 AI': 'ai_not_config',
    '正在识别语音...': 'voice_recognizing',
    '语音识别失败': 'voice_recognize_failed',
    '请授予麦克风权限': 'voice_grant_permission',
    '录音启动失败': 'voice_record_failed',
    '停止录音': 'voice_stop_recording',
    'Whisper 语音输入': 'voice_whisper_input',
    '没有找到匹配的知识点': 'no_matching_topics',
    '系统设计面试指南': 'system_design_guide',
    '面试流程': 'interview_process',
    '开始计时，按步骤完成系统设计': 'start_timer_hint',
    '一键开始全部复习': 'start_all_review',
    '今日复习已完成！': 'review_completed',
    '今日复习工作台': 'today_review_workbench',
    '暂无待复习内容': 'no_review_content',
    '已将知识点推迟到明天': 'deferred_to_tomorrow',
    '切换场景将重新开始面试，当前进度会丢失。确定切换吗？': 'switch_scenario_confirm',
    '确定要删除这个版本吗？': 'confirm_delete_version',
    '缓存已清除，正在重新加载当前领域...': 'cache_cleared_reload',
    '恢复将覆盖当前所有本地数据，此操作不可撤销。是否继续？': 'restore_confirm_msg',
}


def replace_in_content(content):
    """Replace remaining Chinese strings with l10n.get() calls."""
    sorted_map = sorted(EXTRA_MAP.items(), key=lambda x: -len(x[0]))

    for cn, key in sorted_map:
        if len(cn) <= 1:
            continue

        replacement = f"l10n.get('{key}')"
        escaped = re.escape(cn)

        if replacement in content:
            continue

        # Pattern A: Ternary in named params: tooltip: _showFilters ? '隐藏筛选' : '显示筛选'
        # Replace Chinese strings inside ternary expressions
        content = re.sub(
            rf"\?\s*'{escaped}'\s*:",
            f"? {replacement}:",
            content
        )
        content = re.sub(
            rf":\s*'{escaped}'\s*([;\),])",
            f": {replacement}\\1",
            content
        )

        # Pattern B: Map literal values: {1: '入门', 2: '基础', ...}
        # Replace Chinese values in map literals
        content = re.sub(
            rf":\s*'{escaped}'\s*([,\}}])",
            f": {replacement}\\1",
            content
        )

        # Pattern C: Function call args: _buildSortChip('默认', ...)
        content = re.sub(
            rf"\(\s*'{escaped}'\s*,",
            f"({replacement},",
            content
        )

        # Pattern D: const Text('中文', style: ...) -> Text(l10n.get('key'), style: ...)
        content = re.sub(
            rf"const\s+Text\(\s*'{escaped}'\s*,",
            f"Text({replacement},",
            content
        )

        # Pattern E: Text('中文', style: ...) (not const, not already l10n)
        content = re.sub(
            rf"(?<!l10n\.get\()(?<!l10n\.getp\()(?<!const )Text\(\s*'{escaped}'\s*,",
            f"Text({replacement},",
            content
        )

        # Pattern F: Text('中文') - simple
        content = re.sub(
            rf"(?<!l10n\.get\()(?<!l10n\.getp\()(?<!const )Text\(\s*'{escaped}'\s*\)",
            f"Text({replacement})",
            content
        )

        # Pattern G: const Text('中文')
        content = re.sub(
            rf"const\s+Text\(\s*'{escaped}'\s*\)",
            f"Text({replacement})",
            content
        )

        # Pattern H: title: '中文' (string literal)
        content = re.sub(
            rf"title:\s*'{escaped}'",
            f"title: {replacement}",
            content
        )

        # Pattern I: subtitle: '中文'
        content = re.sub(
            rf"subtitle:\s*'{escaped}'",
            f"subtitle: {replacement}",
            content
        )

        # Pattern J: label: '中文' (not in Text widget)
        content = re.sub(
            rf"(?<!Text\()label:\s*'{escaped}'",
            f"label: {replacement}",
            content
        )

        # Pattern K: message: '中文'
        content = re.sub(
            rf"message:\s*'{escaped}'",
            f"message: {replacement}",
            content
        )

        # Pattern L: text: '中文'
        content = re.sub(
            rf"text:\s*'{escaped}'",
            f"text: {replacement}",
            content
        )

        # Pattern M: status: '中文'
        content = re.sub(
            rf"status:\s*'{escaped}'",
            f"status: {replacement}",
            content
        )

        # Pattern N: tooltip: '中文'
        content = re.sub(
            rf"tooltip:\s*'{escaped}'",
            f"tooltip: {replacement}",
            content
        )

        # Pattern O: hintText: '中文'
        content = re.sub(
            rf"hintText:\s*'{escaped}'",
            f"hintText: {replacement}",
            content
        )

        # Pattern P: => '中文' in switch/map
        content = re.sub(
            rf"=>\s*'{escaped}'",
            f"=> {replacement}",
            content
        )

        # Pattern Q: SnackBar(content: Text('中文'))
        content = re.sub(
            rf"SnackBar\(\s*content:\s*(?:const\s+)?Text\(\s*'{escaped}'\s*\)\s*\)",
            f"SnackBar(content: Text({replacement}))",
            content
        )

        # Pattern R: _showUnavailable(context, '中文')
        content = re.sub(
            rf"_showUnavailable\(context,\s*'{escaped}'\)",
            f"_showUnavailable(context, {replacement})",
            content
        )

    # Handle string interpolation patterns
    # Pattern: '$var 个知识点' -> l10n.getp('topics_count_suffix', {'count': '$var'})
    content = re.sub(
        r"'(\$\w+)\s*个知识点'",
        r"l10n.getp('topics_count_suffix', {'count': '\1'})",
        content
    )

    # Pattern: '基于遗忘曲线，今天有 $reviewCount 个知识点待复习'
    # This is complex - leave for manual fix

    return content


def add_l10n_import(content):
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
    if 'context.watch<LocalizationProvider>()' in content:
        return content
    if 'l10n.get(' not in content:
        return content
    lines = content.split('\n')
    new_lines = []
    last_watch_idx = -1
    for i, line in enumerate(lines):
        new_lines.append(line)
        if 'context.watch<' in line and ');' in line:
            last_watch_idx = i
    if last_watch_idx >= 0:
        indent = '    '
        new_lines.insert(last_watch_idx + 1, f'{indent}final l10n = context.watch<LocalizationProvider>();')
    return '\n'.join(new_lines)


def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content
    content = add_l10n_import(content)
    content = replace_in_content(content)
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
            with open(f, 'r') as fh:
                c = fh.read()
                l10n_count = c.count('l10n.get(')
                remaining = 0
                for line in c.split('\n'):
                    s = line.lstrip()
                    if s.startswith('import ') or s.startswith('//') or s.startswith('*') or s.startswith('#'):
                        continue
                    if re.search(r"[\u4e00-\u9fff]", line) and 'l10n.get' not in line:
                        remaining += 1
            print(f"{'✅' if changed else '⏭️'} {os.path.basename(f)}: {l10n_count} l10n, {remaining} remaining Chinese")
        else:
            print(f"❌ Not found: {f}")


if __name__ == '__main__':
    main()
