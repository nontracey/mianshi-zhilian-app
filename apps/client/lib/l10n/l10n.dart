import 'package:flutter/material.dart';

class L10n {
  static const _zh = {
    // 通用
    'app_name': '面试智练',
    'loading': '加载中...',
    'error': '错误',
    'retry': '重试',
    'cancel': '取消',
    'confirm': '确认',
    'save': '保存',
    'delete': '删除',
    'edit': '编辑',
    'back': '返回',
    'search': '搜索',

    // 导航
    'nav_learning': '学习',
    'nav_catalog': '知识',
    'nav_practice': '练习',
    'nav_mastery': '掌握',
    'nav_profile': '我的',

    // 学习中心
    'dashboard_title': '学习中心',
    'current_domain': '领域选择',
    'mastery_percent': '领域掌握度',
    'topic_count': '知识点',
    'review_count': '待复习',
    'start_practice': '进入复述练习',
    'continue_learning': '继续学习',
    'learning_rhythm': '学习节奏',
    'daily_review': '每日 3 个新知识 + 6 个复习',
    'local_first_save': '本地优先保存，完成练习后批量同步。',
    'user_ai_key': '用户自带 AI Key',
    'ai_key_description': 'App 端优先直连，Web 端可走 Worker 代理。',

    // 知识目录
    'catalog_title': '领域知识目录',
    'learn': '学习',
    'practice': '练习',
    'skilled': '熟练',
    'familiar': '熟悉',
    'unfamiliar': '不熟悉',
    'unlearned': '未学习',

    // 知识详情
    'knowledge_learning': '知识学习',
    'recall_practice': '复述练习',
    'start_recall': '开始复述',
    'scoring_criteria': '评分标准',
    'must_cover': '必须覆盖的关键点',
    'bonus_items': '加分项',
    'common_mistakes': '常见错误',

    // 复述练习
    'recall_question': '复述题目',
    'your_answer': '你的回答',
    'answer_hint': '在这里输入你的复述答案...\n\n建议：先说定义 → 再拆机制 → 最后讲场景和误区',
    'get_ai_evaluation': '获取 AI 深度评估',
    'ai_evaluating': 'AI 评估中...',
    'ai_result': 'AI 评估结果',
    'score': '分',
    'missed_points': '遗漏点',
    'error_points': '错误点',
    'optimized_answer': '优化回答',

    // 练习
    'practice_title': 'AI 主动复述',
    'daily_review_title': '今日复习',
    'random_quiz': '随机抽问',
    'mock_interview': '模拟面试',
    'error_review': '错题重练',

    // 掌握度
    'mastery_title': '掌握度看板',
    'total_mastery': '总掌握度',
    'sort_by_score': '按分数排序',
    'sort_by_recent': '按最近练习排序',

    // 个人中心
    'profile_title': '个人中心',
    'account': '账号',
    'login': '登录',
    'logout': '退出登录',
    'login_to_sync': '登录后可同步学习进度到云端',
    'ai_config': 'AI 配置',
    'appearance': '外观与主题',
    'learning_settings': '学习设置',
    'language_settings': '语言设置',
    'data_management': '数据管理',
    'about': '关于面试智练',
    'check_update': '检查更新',

    // 登录
    'login_title': '登录',
    'register_title': '注册账号',
    'username': '用户名',
    'password': '密码',
    'nickname': '昵称',
    'register': '注册',
    'have_account': '已有账号？去登录',
    'no_account': '没有账号？去注册',

    // 数据管理
    'manual_sync': '手动同步',
    'sync_now': '立即同步',
    'data_export': '数据导出',
    'export_success': '数据导出成功',

    // 更新
    'already_latest': '已是最新版本',
    'new_version': '发现新版本',
    'update_now': '立即更新',
    'downloading': '下载中...',
    'install': '安装',
  };

  static const _en = {
    // Common
    'app_name': 'Interview Coach',
    'loading': 'Loading...',
    'error': 'Error',
    'retry': 'Retry',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'save': 'Save',
    'delete': 'Delete',
    'edit': 'Edit',
    'back': 'Back',
    'search': 'Search',

    // Navigation
    'nav_learning': 'Learn',
    'nav_catalog': 'Knowledge',
    'nav_practice': 'Practice',
    'nav_mastery': 'Mastery',
    'nav_profile': 'Profile',

    // Dashboard
    'dashboard_title': 'Learning Center',
    'current_domain': 'Domain Selection',
    'mastery_percent': 'Mastery',
    'topic_count': 'Topics',
    'review_count': 'Review',
    'start_practice': 'Start Recall Practice',
    'continue_learning': 'Continue Learning',
    'learning_rhythm': 'Learning Rhythm',
    'daily_review': '3 new topics + 6 reviews daily',
    'local_first_save': 'Local-first, sync after practice.',
    'user_ai_key': 'User AI Key',
    'ai_key_description': 'App direct connection, Web via Worker proxy.',

    // Catalog
    'catalog_title': 'Domain Knowledge Catalog',
    'learn': 'Learn',
    'practice': 'Practice',
    'skilled': 'Skilled',
    'familiar': 'Familiar',
    'unfamiliar': 'Unfamiliar',
    'unlearned': 'Unlearned',

    // Topic Detail
    'knowledge_learning': 'Knowledge',
    'recall_practice': 'Recall',
    'start_recall': 'Start Recall',
    'scoring_criteria': 'Scoring Criteria',
    'must_cover': 'Must Cover',
    'bonus_items': 'Bonus Items',
    'common_mistakes': 'Common Mistakes',

    // Recall
    'recall_question': 'Recall Question',
    'your_answer': 'Your Answer',
    'answer_hint': 'Enter your recall answer here...\n\nTip: Start with definition → Explain mechanism → Discuss scenarios',
    'get_ai_evaluation': 'Get AI Evaluation',
    'ai_evaluating': 'AI Evaluating...',
    'ai_result': 'AI Evaluation Result',
    'score': 'Score',
    'missed_points': 'Missed Points',
    'error_points': 'Error Points',
    'optimized_answer': 'Optimized Answer',

    // Practice
    'practice_title': 'AI Recall Practice',
    'daily_review_title': 'Daily Review',
    'random_quiz': 'Random Quiz',
    'mock_interview': 'Mock Interview',
    'error_review': 'Error Review',

    // Mastery
    'mastery_title': 'Mastery Dashboard',
    'total_mastery': 'Total Mastery',
    'sort_by_score': 'Sort by Score',
    'sort_by_recent': 'Sort by Recent',

    // Profile
    'profile_title': 'Profile',
    'account': 'Account',
    'login': 'Login',
    'logout': 'Logout',
    'login_to_sync': 'Login to sync progress to cloud',
    'ai_config': 'AI Configuration',
    'appearance': 'Appearance',
    'learning_settings': 'Learning Settings',
    'language_settings': 'Language',
    'data_management': 'Data Management',
    'about': 'About',
    'check_update': 'Check Update',

    // Login
    'login_title': 'Login',
    'register_title': 'Register',
    'username': 'Username',
    'password': 'Password',
    'nickname': 'Nickname',
    'register': 'Register',
    'have_account': 'Already have an account? Login',
    'no_account': 'No account? Register',

    // Data
    'manual_sync': 'Manual Sync',
    'sync_now': 'Sync Now',
    'data_export': 'Export Data',
    'export_success': 'Data exported successfully',

    // Update
    'already_latest': 'Already latest version',
    'new_version': 'New version available',
    'update_now': 'Update Now',
    'downloading': 'Downloading...',
    'install': 'Install',
  };

  static String get(String key, String language) {
    final map = language == 'en' ? _en : _zh;
    return map[key] ?? key;
  }

  static List<Locale> get supportedLocales => [
    const Locale('zh'),
    const Locale('en'),
  ];
}
