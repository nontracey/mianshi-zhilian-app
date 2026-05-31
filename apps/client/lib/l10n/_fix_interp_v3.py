#!/usr/bin/env python3
"""Replace interpolated Chinese strings with l10n.getp() calls."""
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (file, old, new, key, en)
R = []

def add(f, old, new, key=None, en=None):
    R.append((f, old, new, key, en))

# today_review_page.dart
add("pages/practice/today_review_page.dart",
    "return '最近得分 $lastScore 分（已练习 $practiceCount 次），需要重新组织回答';",
    "return l10n.getp('最近得分 {lastScore} 分（已练习 {practiceCount} 次），需要重新组织回答', {'lastScore': lastScore, 'practiceCount': practiceCount});",
    "最近得分 {lastScore} 分（已练习 {practiceCount} 次），需要重新组织回答",
    "Last score: {lastScore} (practiced {practiceCount} times), needs reorganization")

add("pages/practice/today_review_page.dart",
    "return '高频知识点，当前 $score 分，未达熟练阈值';",
    "return l10n.getp('高频知识点，当前 {score} 分，未达熟练阈值', {'score': score});",
    "高频知识点，当前 {score} 分，未达熟练阈值",
    "High-frequency topic, current {score} points, below proficiency threshold")

add("pages/practice/today_review_page.dart",
    "return '距上次练习已 $days 天，建议尽快复习巩固';",
    "return l10n.getp('距上次练习已 {days} 天，建议尽快复习巩固', {'days': days});",
    "距上次练习已 {days} 天，建议尽快复习巩固",
    "{days} days since last practice, review recommended soon")

add("pages/practice/today_review_page.dart",
    "return '从 $previous 分降至 $latest 分（下降 $diff 分）';",
    "return l10n.getp('从 {previous} 分降至 {latest} 分（下降 {diff} 分）', {'previous': previous, 'latest': latest, 'diff': diff});",
    "从 {previous} 分降至 {latest} 分（下降 {diff} 分）",
    "Dropped from {previous} to {latest} ({diff} points decrease)")

add("pages/practice/today_review_page.dart",
    "if (daysOverdue > 3) return '已逾期 $daysOverdue 天，遗忘风险极高';",
    "if (daysOverdue > 3) return l10n.getp('已逾期 {daysOverdue} 天，遗忘风险极高', {'daysOverdue': daysOverdue});",
    "已逾期 {daysOverdue} 天，遗忘风险极高",
    "{daysOverdue} days overdue, high forgetting risk")

add("pages/practice/today_review_page.dart",
    "if (daysOverdue > 0) return '已逾期 $daysOverdue 天，遗忘风险增加';",
    "if (daysOverdue > 0) return l10n.getp('已逾期 {daysOverdue} 天，遗忘风险增加', {'daysOverdue': daysOverdue});",
    "已逾期 {daysOverdue} 天，遗忘风险增加",
    "{daysOverdue} days overdue, increased forgetting risk")

add("pages/practice/today_review_page.dart",
    "if (daysSincePractice > 0) return '距上次练习 $daysSincePractice 天，按遗忘曲线到期';",
    "if (daysSincePractice > 0) return l10n.getp('距上次练习 {daysSincePractice} 天，按遗忘曲线到期', {'daysSincePractice': daysSincePractice});",
    "距上次练习 {daysSincePractice} 天，按遗忘曲线到期",
    "{daysSincePractice} days since last practice, due by forgetting curve")

add("pages/practice/today_review_page.dart",
    "return '提前复习（原定 ${-daysOverdue} 天后）';",
    "return l10n.getp('提前复习（原定 {days} 天后）', {'days': -daysOverdue});",
    "提前复习（原定 {days} 天后）",
    "Early review (originally due in {days} days)")

add("pages/practice/today_review_page.dart",
    ": '共 $totalCount 个知识点等待复习',",
    ": l10n.getp('共 {totalCount} 个知识点等待复习', {'totalCount': totalCount}),",
    "共 {totalCount} 个知识点等待复习",
    "{totalCount} topics waiting for review")

add("pages/practice/today_review_page.dart",
    "SnackBar(content: Text('已将「${topic.title}」推迟到明天')),",
    "SnackBar(content: Text(l10n.getp('已将「{title}」推迟到明天', {'title': topic.title}))),",
    "已将「{title}」推迟到明天",
    'Postponed "{title}" to tomorrow')

add("pages/practice/today_review_page.dart",
    "SnackBar(content: Text('已将「${topic.title}」推迟')),",
    "SnackBar(content: Text(l10n.getp('已将「{title}」推迟', {'title': topic.title}))),",
    "已将「{title}」推迟",
    'Postponed "{title}"')

add("pages/practice/today_review_page.dart",
    "'${topic.estimatedMinutes} 分钟',",
    "l10n.getp('{minutes} 分钟', {'minutes': topic.estimatedMinutes}),",
    "{minutes} 分钟",
    "{minutes} min")

# dashboard_page.dart
add("pages/learning/dashboard_page.dart",
    "if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';",
    "if (diff.inMinutes < 60) return l10n.getp('{minutes} 分钟前', {'minutes': diff.inMinutes});",
    "{minutes} 分钟前",
    "{minutes} min ago")

add("pages/learning/dashboard_page.dart",
    "if (diff.inHours < 24) return '${diff.inHours} 小时前';",
    "if (diff.inHours < 24) return l10n.getp('{hours} 小时前', {'hours': diff.inHours});",
    "{hours} 小时前",
    "{hours} hours ago")

add("pages/learning/dashboard_page.dart",
    "if (diff.inDays < 7) return '${diff.inDays} 天前';",
    "if (diff.inDays < 7) return l10n.getp('{days} 天前', {'days': diff.inDays});",
    "{days} 天前",
    "{days} days ago")

add("pages/learning/dashboard_page.dart",
    "'${domain.topicCount} 考点',",
    "l10n.getp('{count} 考点', {'count': domain.topicCount}),",
    "{count} 考点",
    "{count} topics")

add("pages/learning/dashboard_page.dart",
    "'$practiceCount 练习',",
    "l10n.getp('{count} 练习', {'count': practiceCount}),",
    "{count} 练习",
    "{count} practices")

add("pages/learning/dashboard_page.dart",
    "'进度 ${widget.masteryPercent}%',",
    "l10n.getp('进度 {percent}%', {'percent': widget.masteryPercent}),",
    "进度 {percent}%",
    "Progress {percent}%")

add("pages/learning/dashboard_page.dart",
    "'考点 ${widget.domain.topicCount}',",
    "l10n.getp('考点 {count}', {'count': widget.domain.topicCount}),",
    "考点 {count}",
    "Topics {count}")

add("pages/learning/dashboard_page.dart",
    "'${domain.topicCount} 个知识点',",
    "l10n.getp('{count} 个知识点', {'count': domain.topicCount}),",
    "{count} 个知识点",
    "{count} topics")

# catalog_page.dart
add("pages/learning/catalog_page.dart",
    "'$totalTopics 个知识点',",
    "l10n.getp('{count} 个知识点', {'count': totalTopics}),",
    None, None)

add("pages/learning/catalog_page.dart",
    "'${topic.estimatedMinutes}分钟',",
    "l10n.getp('{minutes}分钟', {'minutes': topic.estimatedMinutes}),",
    "{minutes}分钟",
    "{minutes}min")

add("pages/learning/catalog_page.dart",
    "'$score分',",
    "l10n.getp('{score}分', {'score': score}),",
    "{score}分",
    "{score}pts")

add("pages/learning/catalog_page.dart",
    "if (pastDiff.inMinutes < 60) return '${pastDiff.inMinutes}分钟前';",
    "if (pastDiff.inMinutes < 60) return l10n.getp('{n}分钟前', {'n': pastDiff.inMinutes});",
    "{n}分钟前",
    "{n}min ago")

add("pages/learning/catalog_page.dart",
    "if (pastDiff.inHours < 24) return '${pastDiff.inHours}小时前';",
    "if (pastDiff.inHours < 24) return l10n.getp('{n}小时前', {'n': pastDiff.inHours});",
    "{n}小时前",
    "{n}h ago")

add("pages/learning/catalog_page.dart",
    "return '${pastDiff.inDays}天前';",
    "return l10n.getp('{n}天前', {'n': pastDiff.inDays});",
    "{n}天前",
    "{n}d ago")

add("pages/learning/catalog_page.dart",
    "if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';",
    "if (diff.inMinutes < 60) return l10n.getp('{n}分钟后', {'n': diff.inMinutes});",
    "{n}分钟后",
    "{n}min later")

add("pages/learning/catalog_page.dart",
    "if (diff.inHours < 24) return '${diff.inHours}小时后';",
    "if (diff.inHours < 24) return l10n.getp('{n}小时后', {'n': diff.inHours});",
    "{n}小时后",
    "{n}h later")

add("pages/learning/catalog_page.dart",
    "return '${diff.inDays}天后';",
    "return l10n.getp('{n}天后', {'n': diff.inDays});",
    "{n}天后",
    "{n}d later")

add("pages/learning/catalog_page.dart",
    "'$count 题',",
    "l10n.getp('{count} 题', {'count': count}),",
    "{count} 题",
    "{count} questions")

# navigation_rail_panel.dart
add("widgets/navigation_rail_panel.dart",
    "value: '$streakDays 天',",
    "value: l10n.getp('{days} 天', {'days': streakDays}),",
    "{days} 天",
    "{days} days")

add("widgets/navigation_rail_panel.dart",
    "message: '连续学习 $streakDays 天',",
    "message: l10n.getp('连续学习 {days} 天', {'days': streakDays}),",
    "连续学习 {days} 天",
    "{days} day streak")

# header_bar.dart
add("widgets/header_bar.dart",
    "'${_searchResults.length} 项',",
    "l10n.getp('{count} 项', {'count': _searchResults.length}),",
    "{count} 项",
    "{count} items")

# recall_page.dart
add("pages/practice/recall_page.dart",
    "'请用自己的话解释 ${topic.title} 的核心内容。',",
    "l10n.getp('请用自己的话解释 {title} 的核心内容。', {'title': topic.title}),",
    "请用自己的话解释 {title} 的核心内容。",
    "Explain the core content of {title} in your own words.")

add("pages/practice/recall_page.dart",
    "'面试官关注：${topic.interviewerFocus}',",
    "l10n.getp('面试官关注：{focus}', {'focus': topic.interviewerFocus}),",
    "面试官关注：{focus}",
    "Interviewer focus: {focus}")

add("pages/practice/recall_page.dart",
    "'第 $current / $total 题',",
    "l10n.getp('第 {current} / {total} 题', {'current': current, 'total': total}),",
    "第 {current} / {total} 题",
    "Question {current} of {total}")

# mock_interview_page.dart
add("pages/practice/mock_interview_page.dart",
    ": '请解释 ${topic.title} 的核心概念');",
    ": l10n.getp('请解释 {title} 的核心概念', {'title': topic.title}));",
    "请解释 {title} 的核心概念",
    "Explain the core concept of {title}")

add("pages/practice/mock_interview_page.dart",
    "'问题 ${_currentIndex + 1}',",
    "l10n.getp('问题 {index}', {'index': _currentIndex + 1}),",
    "问题 {index}",
    "Question {index}")

add("pages/practice/mock_interview_page.dart",
    "'第 ${_followUpHistory.length + 1} 轮',",
    "l10n.getp('第 {round} 轮', {'round': _followUpHistory.length + 1}),",
    "第 {round} 轮",
    "Round {round}")

add("pages/practice/mock_interview_page.dart",
    "'面试官关注：${topic.interviewerFocus}',",
    "l10n.getp('面试官关注：{focus}', {'focus': topic.interviewerFocus}),",
    None, None)

add("pages/practice/mock_interview_page.dart",
    "'${_answerController.text.length} 字',",
    "l10n.getp('{count} 字', {'count': _answerController.text.length}),",
    "{count} 字",
    "{count} characters")

add("pages/practice/mock_interview_page.dart",
    "'匹配 ${_activeTopicIds.length} / ${widget.topicIds.length} 题',",
    "l10n.getp('匹配 {matched} / {total} 题', {'matched': _activeTopicIds.length, 'total': widget.topicIds.length}),",
    "匹配 {matched} / {total} 题",
    "Matched {matched} / {total} questions")

add("pages/practice/mock_interview_page.dart",
    "'追问记录（${_followUpHistory.length} 轮）',",
    "l10n.getp('追问记录（{count} 轮）', {'count': _followUpHistory.length}),",
    "追问记录（{count} 轮）",
    "Follow-up history ({count} rounds)")

add("pages/practice/mock_interview_page.dart",
    "'本题用时 ${_formatDuration(_questionDurations.last)}',",
    "l10n.getp('本题用时 {duration}', {'duration': _formatDuration(_questionDurations.last)}),",
    "本题用时 {duration}",
    "Time spent: {duration}")

add("pages/practice/mock_interview_page.dart",
    "'$weakCount 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。',",
    "l10n.getp('{count} 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。', {'count': weakCount}),",
    "{count} 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。",
    "{count} questions scored below 60, review weak topics before next mock interview.")

add("pages/practice/mock_interview_page.dart",
    "'用时 ${_formatDuration(duration)}',",
    "l10n.getp('用时 {duration}', {'duration': _formatDuration(duration)}),",
    "用时 {duration}",
    "Time: {duration}")

add("pages/practice/mock_interview_page.dart",
    "'$score 分',",
    "l10n.getp('{score} 分', {'score': score}),",
    "{score} 分",
    "{score} points")

# topic_detail_page.dart
add("pages/learning/topic_detail_page.dart",
    "content: Text('AI 评估失败：$e'),",
    "content: Text(l10n.getp('AI 评估失败：{error}', {'error': e})),",
    "AI 评估失败：{error}",
    "AI evaluation failed: {error}")

add("pages/learning/topic_detail_page.dart",
    "'${topic.estimatedMinutes} 分钟',",
    "l10n.getp('{minutes} 分钟', {'minutes': topic.estimatedMinutes}),",
    None, None)

add("pages/learning/topic_detail_page.dart",
    "'${followUps.length} 题',",
    "l10n.getp('{count} 题', {'count': followUps.length}),",
    None, None)

add("pages/learning/topic_detail_page.dart",
    "'${answerController.text.length} 字',",
    "l10n.getp('{count} 字', {'count': answerController.text.length}),",
    None, None)

# answer_versions_page.dart
add("pages/practice/answer_versions_page.dart",
    "text: '请帮我改进以下面试回答：\\n\\n$content',",
    "text: l10n.getp('请帮我改进以下面试回答：\\n\\n{content}', {'content': content}),",
    "请帮我改进以下面试回答：\\n\\n{content}",
    "Please help improve this interview answer:\\n\\n{content}")

add("pages/practice/answer_versions_page.dart",
    "'原始回答：\\n$originalAnswer';",
    "l10n.getp('原始回答：\\n{answer}', {'answer': originalAnswer});",
    "原始回答：\\n{answer}",
    "Original answer:\\n{answer}")

add("pages/practice/answer_versions_page.dart",
    "onError('AI 改进失败: $e');",
    "onError(l10n.getp('AI 改进失败: {error}', {'error': e}));",
    "AI 改进失败: {error}",
    "AI improvement failed: {error}")

# interview_prep_page.dart
add("pages/prep/interview_prep_page.dart",
    "if (plan.techStack.isNotEmpty) parts.add('技术栈：${plan.techStack}');",
    "if (plan.techStack.isNotEmpty) parts.add(l10n.getp('技术栈：{techStack}', {'techStack': plan.techStack}));",
    "技术栈：{techStack}",
    "Tech stack: {techStack}")

add("pages/prep/interview_prep_page.dart",
    "if (plan.dailyMinutes > 0) parts.add('每日 ${plan.dailyMinutes} 分钟');",
    "if (plan.dailyMinutes > 0) parts.add(l10n.getp('每日 {minutes} 分钟', {'minutes': plan.dailyMinutes}));",
    "每日 {minutes} 分钟",
    "{minutes} min/day")

add("pages/prep/interview_prep_page.dart",
    "Expanded(child: Text('每日投入 $dailyMinutes 分钟')),",
    "Expanded(child: Text(l10n.getp('每日投入 {minutes} 分钟', {'minutes': dailyMinutes}))),",
    "每日投入 {minutes} 分钟",
    "{minutes} min/day investment")

add("pages/prep/interview_prep_page.dart",
    "'${matchedTopics.length} 项匹配',",
    "l10n.getp('{count} 项匹配', {'count': matchedTopics.length}),",
    "{count} 项匹配",
    "{count} matches")

# profile_page.dart
add("pages/profile/profile_page.dart",
    "SnackBar(content: Text('拍照失败: $e')),",
    "SnackBar(content: Text(l10n.getp('拍照失败: {error}', {'error': e}))),",
    "拍照失败: {error}",
    "Photo capture failed: {error}")

add("pages/profile/profile_page.dart",
    "SnackBar(content: Text('选择图片失败: $e')),",
    "SnackBar(content: Text(l10n.getp('选择图片失败: {error}', {'error': e}))),",
    "选择图片失败: {error}",
    "Image selection failed: {error}")

add("pages/profile/profile_page.dart",
    ").showSnackBar(SnackBar(content: Text('$name 功能待开通，可先使用本地数据和 WebDAV 备份')));",
    ").showSnackBar(SnackBar(content: Text(l10n.getp('{name} 功能待开通，可先使用本地数据和 WebDAV 备份', {'name': name}))));",
    "{name} 功能待开通，可先使用本地数据和 WebDAV 备份",
    "{name} feature coming soon, use local data and WebDAV backup for now")

add("pages/profile/profile_page.dart",
    "title: '当前方式：${_methodLabel(syncSettings.method, l10n)}',",
    "title: l10n.getp('当前方式：{method}', {'method': _methodLabel(syncSettings.method, l10n)}),",
    "当前方式：{method}",
    "Current method: {method}")

add("pages/profile/profile_page.dart",
    "SnackBar(content: Text('${_methodLabel(value, l10n)} 功能待开通')),",
    "SnackBar(content: Text(l10n.getp('{method} 功能待开通', {'method': _methodLabel(value, l10n)}))),",
    "{method} 功能待开通",
    "{method} feature coming soon")

add("pages/profile/profile_page.dart",
    "_updateMessage = '发现新版本 v${updateInfo.version}';",
    "_updateMessage = l10n.getp('发现新版本 v{version}', {'version': updateInfo.version});",
    "发现新版本 v{version}",
    "New version v{version} available")

add("pages/profile/profile_page.dart",
    "title: Text('发现新版本 v${updateInfo.version}'),",
    "title: Text(l10n.getp('发现新版本 v{version}', {'version': updateInfo.version})),",
    None, None)

add("pages/profile/profile_page.dart",
    "Text('发布日期：${updateInfo.releaseDate}'),",
    "Text(l10n.getp('发布日期：{date}', {'date': updateInfo.releaseDate})),",
    "发布日期：{date}",
    "Release date: {date}")

add("pages/profile/profile_page.dart",
    "'平台：${UpdateService.formatSize(updateInfo.platforms.values.first.size)}',",
    "l10n.getp('平台：{size}', {'size': UpdateService.formatSize(updateInfo.platforms.values.first.size)}),",
    "平台：{size}",
    "Platform: {size}")

add("pages/profile/profile_page.dart",
    "Text('正在下载 v${updateInfo.version}...'),",
    "Text(l10n.getp('正在下载 v{version}...', {'version': updateInfo.version})),",
    "正在下载 v{version}...",
    "Downloading v{version}...")

add("pages/profile/profile_page.dart",
    "title: Text('v$version 下载完成'),",
    "title: Text(l10n.getp('v{version} 下载完成', {'version': version})),",
    "v{version} 下载完成",
    "v{version} download complete")

add("pages/profile/profile_page.dart",
    "'当前：${settings.contentBaseUrl}',",
    "l10n.getp('当前：{url}', {'url': settings.contentBaseUrl}),",
    "当前：{url}",
    "Current: {url}")

add("pages/profile/profile_page.dart",
    "'默认：${AppSettings.defaultWorkerApiUrl}/content/test',",
    "l10n.getp('默认：{url}/content/test', {'url': AppSettings.defaultWorkerApiUrl}),",
    "默认：{url}/content/test",
    "Default: {url}/content/test")

add("pages/profile/profile_page.dart",
    "'默认：${AppSettings.defaultWorkerApiUrl}/content/production',",
    "l10n.getp('默认：{url}/content/production', {'url': AppSettings.defaultWorkerApiUrl}),",
    "默认：{url}/content/production",
    "Default: {url}/content/production")

# practice_page.dart
add("pages/practice/practice_page.dart",
    "subtitle: '基于遗忘曲线，今天有 $reviewCount 个知识点待复习',",
    "subtitle: l10n.getp('基于遗忘曲线，今天有 {count} 个知识点待复习', {'count': reviewCount}),",
    "基于遗忘曲线，今天有 {count} 个知识点待复习",
    "Based on forgetting curve, {count} topics to review today")

# system_design_page.dart
add("pages/practice/system_design_page.dart",
    "title: Text('练习：${topic['title']}'),",
    "title: Text(l10n.getp('练习：{title}', {'title': topic['title']})),",
    "练习：{title}",
    "Practice: {title}")


def main():
    new_keys = {}
    changes = 0

    for file_path, old, new, key, en_val in R:
        full_path = os.path.join(BASE, file_path)
        if not os.path.exists(full_path):
            print(f"SKIP: {file_path}")
            continue

        with open(full_path, 'r') as f:
            content = f.read()

        if old not in content:
            print(f"  MISS: {file_path}: {old[:60]}...")
            continue

        content = content.replace(old, new, 1)
        changes += 1

        with open(full_path, 'w') as f:
            f.write(content)

        if key and en_val:
            new_keys[key] = en_val

    print(f"\nTotal changes: {changes}")
    print(f"New keys to add: {len(new_keys)}")

    if new_keys:
        print("\n--- Add to _zh map ---")
        for key in sorted(new_keys.keys()):
            print(f"      '{key}': '{key}',")
        print("\n--- Add to _en map ---")
        for key in sorted(new_keys.keys()):
            print(f"      '{key}': '{new_keys[key]}',")

if __name__ == '__main__':
    main()
