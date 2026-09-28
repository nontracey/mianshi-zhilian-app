/// 上下文与记忆（§7.4）。
///
/// 每轮上下文固定由六部分组成：
/// 1. 短版教练规则；
/// 2. 当前 JD / 简历 / 项目选择及模式（只取与本题关联的片段，附档案与版本）；
/// 3. 当前题目或教学 checkpoint（含权威日期与提示记录）；
/// 4. 最近必要问答；
/// 5. 检索证据；
/// 6. 当前允许调用的工具。
///
/// 会话变长时**优先压缩旧闲聊与重复资料**，为模型输出和工具结果预留空间；不整包
/// 发送历史会话、全部 JD、整个项目库。总结只帮助续接，不替代证据。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';
import '../domain/goal.dart';
import '../domain/resume.dart';
import '../domain/session.dart';
import '../tools/tool_contract.dart';

/// 检索到的证据片段。
///
/// 这里不直接依赖检索实现，由调用方把 `RetrievalHit` 映射成该结构，避免 context
/// 层与 knowledge 层相互耦合。
class ContextEvidence {
  const ContextEvidence({
    required this.citationId,
    required this.title,
    required this.snippet,
    this.sourceId,
    this.knowledgeItemId,
  });

  final String citationId;
  final String title;
  final String snippet;
  final String? sourceId;
  final String? knowledgeItemId;
}

/// 与本题关联的 JD 要求片段。
class ContextRequirement {
  const ContextRequirement({
    required this.id,
    required this.title,
    required this.importance,
    this.summary,
  });

  final RequirementId id;
  final String title;
  final Importance importance;
  final String? summary;

  factory ContextRequirement.fromDomain(GoalRequirement r) =>
      ContextRequirement(
        id: r.id,
        title: r.title,
        importance: r.importance,
        summary: r.summary,
      );
}

/// 与本题关联的简历主张片段。
class ContextClaim {
  const ContextClaim({
    required this.id,
    required this.statement,
    required this.status,
    this.projectId,
  });

  final ClaimId id;
  final String statement;
  final ClaimStatus status;
  final ProjectId? projectId;

  factory ContextClaim.fromDomain(ResumeClaim c) => ContextClaim(
    id: c.id,
    statement: c.statement,
    status: c.status,
    projectId: c.projectId,
  );
}

/// 与本题关联的项目片段（只带判定依据需要的字段，不整包发送项目库）。
class ContextProject {
  const ContextProject({
    required this.id,
    required this.name,
    this.techStack,
    this.metrics,
    this.goal,
    this.responsibilities,
    this.originalSpan,
  });

  final ProjectId id;
  final String name;
  final String? techStack;
  final String? metrics;
  final String? goal;
  final String? responsibilities;
  final String? originalSpan;

  factory ContextProject.fromDomain(Project p) => ContextProject(
    id: p.id,
    name: p.name,
    techStack: p.techStack,
    metrics: p.metrics,
    goal: p.goal,
    responsibilities: p.responsibilities,
    originalSpan: p.originalSpan,
  );
}

/// 上下文预算（按字符计，确定性且便于测试）。
class ContextBudget {
  const ContextBudget({
    this.maxChars = 12000,
    this.reserveForOutputChars = 2200,
    this.reserveForToolChars = 1500,
    this.maxRecentMessages = 8,
    this.maxEvidenceItems = 8,
  });

  final int maxChars;

  /// 给模型输出预留。
  final int reserveForOutputChars;

  /// 给工具结果预留。
  final int reserveForToolChars;

  /// 最多携带的历史消息条数（在预算允许的前提下还会再裁）。
  final int maxRecentMessages;

  final int maxEvidenceItems;

  /// 可供规则/选择/范围/问答/证据使用的字符数。
  int get availableChars {
    final available = maxChars - reserveForOutputChars - reserveForToolChars;
    return available < 0 ? 0 : available;
  }
}

/// 一次上下文构建请求。
class ContextRequest {
  const ContextRequest({
    required this.profileId,
    required this.mode,
    required this.rules,
    this.goalId,
    this.goalRevision,
    this.resumeId,
    this.resumeRevision,
    this.projectIds = const [],
    this.requirements = const [],
    this.claims = const [],
    this.projects = const [],
    this.knowledgeTitle,
    this.knowledgeItemId,
    this.reviewPointLabel,
    this.reviewPointId,
    this.checkpoint,
    this.recentMessages = const [],
    this.evidence = const [],
    this.allowedTools = const [],
    this.budget = const ContextBudget(),
  });

  final ProfileId profileId;
  final SessionMode mode;

  /// 短版教练规则（已按模式装配）。
  final String rules;

  final GoalId? goalId;
  final int? goalRevision;
  final ResumeId? resumeId;
  final int? resumeRevision;
  final List<ProjectId> projectIds;

  final List<ContextRequirement> requirements;
  final List<ContextClaim> claims;
  final List<ContextProject> projects;

  final KnowledgeItemId? knowledgeItemId;
  final String? knowledgeTitle;
  final ReviewPointId? reviewPointId;
  final String? reviewPointLabel;
  final LessonCheckpoint? checkpoint;

  final List<CoachMessage> recentMessages;
  final List<ContextEvidence> evidence;
  final List<ToolContract> allowedTools;

  final ContextBudget budget;
}

/// 构建结果。各段正文都可单独断言，便于测试与排错。
class CoachContext {
  const CoachContext({
    required this.rulesSection,
    required this.selectionSection,
    required this.scopeSection,
    required this.recentQaSection,
    required this.evidenceSection,
    required this.toolsSection,
    required this.rendered,
    required this.citationIds,
    required this.keptMessageIds,
    required this.droppedMessageCount,
    required this.duplicateMessageCount,
    required this.droppedEvidenceCount,
    required this.truncated,
    required this.usedChars,
    required this.availableChars,
  });

  final String rulesSection;
  final String selectionSection;
  final String scopeSection;
  final String recentQaSection;
  final String evidenceSection;
  final String toolsSection;

  /// 组装后的完整上下文（可直接作为 system/user 前缀）。
  final String rendered;

  /// 本次实际携带的引用 ID，用于校验引用可定位。
  final List<String> citationIds;
  final List<MessageId> keptMessageIds;

  final int droppedMessageCount;

  /// 因重复被合并掉的消息数（重复资料优先压缩）。
  final int duplicateMessageCount;

  final int droppedEvidenceCount;
  final bool truncated;

  final int usedChars;
  final int availableChars;

  Map<String, Object?> toJson() => {
    'citationIds': citationIds,
    'keptMessageIds': keptMessageIds,
    'droppedMessageCount': droppedMessageCount,
    'duplicateMessageCount': duplicateMessageCount,
    'droppedEvidenceCount': droppedEvidenceCount,
    'truncated': truncated,
    'usedChars': usedChars,
    'availableChars': availableChars,
  };
}

/// 上下文构建器。
class ContextBuilder {
  const ContextBuilder();

  CoachContext build(ContextRequest request) {
    if (request.recentMessages.any((m) => m.profileId != request.profileId) ||
        (request.checkpoint != null &&
            request.checkpoint!.profileId != request.profileId)) {
      throw StateError('Context contains data from another profile');
    }
    final budget = request.budget;

    final rulesSection = _section('rules', request.rules.trim());
    final fullSelection = _selection(request);
    final scopeSection = _scope(request);
    final toolsSection = _tools(request.allowedTools);

    // Include all section headings and separators in the budget. Never cut
    // policy rules or silently send a request above the configured limit.
    final mandatoryChars =
        rulesSection.length + scopeSection.length + toolsSection.length + 64;
    if (mandatoryChars >= budget.availableChars) {
      throw StateError('Context budget cannot fit rules and current scope');
    }
    final selectionAllowance = ((budget.availableChars - mandatoryChars) * 0.45)
        .floor();
    final selectionSection = _clipSelection(fullSelection, selectionAllowance);
    final remaining =
        budget.availableChars - mandatoryChars - selectionSection.length;

    // 证据优先于历史问答：证据是判定依据，历史问答只帮助续接。
    final evidenceBudget = (remaining * 0.6).floor();
    final qaBudget = remaining - evidenceBudget;

    final evidence = _selectEvidence(
      request.evidence,
      evidenceBudget,
      maxItems: budget.maxEvidenceItems,
    );
    final qa = _selectMessages(
      request.recentMessages,
      qaBudget,
      maxItems: budget.maxRecentMessages,
    );

    final evidenceSection = _section(
      'retrieved_evidence',
      evidence.lines.join('\n'),
    );
    final recentQaSection = _section('recent_qa', qa.lines.join('\n'));

    final rendered = [
      rulesSection,
      selectionSection,
      scopeSection,
      recentQaSection,
      evidenceSection,
      toolsSection,
    ].where((s) => s.trim().isNotEmpty).join('\n\n');

    final usedChars = rendered.length;
    return CoachContext(
      rulesSection: rulesSection,
      selectionSection: selectionSection,
      scopeSection: scopeSection,
      recentQaSection: recentQaSection,
      evidenceSection: evidenceSection,
      toolsSection: toolsSection,
      rendered: rendered,
      citationIds: evidence.citationIds,
      keptMessageIds: qa.keptIds,
      droppedMessageCount: qa.dropped,
      duplicateMessageCount: qa.duplicates,
      droppedEvidenceCount: evidence.dropped,
      truncated:
          selectionSection != fullSelection ||
          qa.dropped > 0 ||
          evidence.dropped > 0,
      usedChars: usedChars,
      availableChars: budget.availableChars,
    );
  }

  String _clipSelection(String selection, int limit) {
    if (selection.length <= limit) return selection;
    const marker = '\n[selection truncated; omitted material is not evidence]';
    if (limit < marker.length) return '';
    final lines = <String>[];
    var length = marker.length;
    for (final line in selection.split('\n')) {
      if (length + line.length + 1 > limit) break;
      lines.add(line);
      length += line.length + 1;
    }
    return lines.join('\n') + marker;
  }

  // ── 各段 ──────────────────────────────────────────────────────────

  String _selection(ContextRequest r) {
    final buf = StringBuffer()
      ..writeln('mode: ${r.mode.promptToken}')
      ..writeln('profile: ${r.profileId}');
    if (r.goalId != null) {
      buf.writeln('goal: ${r.goalId} (revision ${r.goalRevision ?? 1})');
    }
    if (r.resumeId != null) {
      buf.writeln('resume: ${r.resumeId} (revision ${r.resumeRevision ?? 1})');
    }
    if (r.projectIds.isNotEmpty) {
      buf.writeln('projects: ${r.projectIds.join(', ')}');
    }

    // 只取与本题关联的要求/主张片段，并标注它们是“要求”还是“本人主张”。
    if (r.requirements.isNotEmpty) {
      buf.writeln('linked_requirements:');
      for (final req in r.requirements) {
        final summary = req.summary == null ? '' : ' :: ${req.summary}';
        buf.writeln(
          '  - [${req.id}] (${req.importance.name}) '
          '${req.title}$summary',
        );
      }
    }
    if (r.claims.isNotEmpty) {
      buf.writeln('linked_claims:');
      for (final claim in r.claims) {
        final project = claim.projectId == null
            ? ''
            : ' project=${claim.projectId}';
        buf.writeln(
          '  - [${claim.id}] (${claim.status.name})$project '
          '${claim.statement}',
        );
      }
    }
    if (r.projects.isNotEmpty) {
      buf.writeln('linked_projects:');
      for (final project in r.projects) {
        final stack = project.techStack == null
            ? ''
            : ' stack=${project.techStack}';
        final metrics = project.metrics == null
            ? ''
            : ' metrics=${project.metrics}';
        buf.writeln('  - [${project.id}] ${project.name}$stack$metrics');
        for (final entry in {
          'goal': project.goal,
          'responsibilities': project.responsibilities,
          'original_span': project.originalSpan,
        }.entries) {
          final text = entry.value;
          if (text != null) {
            buf.writeln(
              '    ${entry.key}: ${text.substring(0, text.length.clamp(0, 1200))}',
            );
          }
        }
      }
    }
    return _section('current_selection', buf.toString().trimRight());
  }

  String _scope(ContextRequest r) {
    final buf = StringBuffer();
    buf.writeln(
      'knowledge_item: ${r.knowledgeItemId ?? "none"}'
      '${r.knowledgeTitle == null ? '' : ' — ${r.knowledgeTitle}'}',
    );
    buf.writeln(
      'review_point: ${r.reviewPointId ?? "none"}'
      '${r.reviewPointLabel == null ? '' : ' — ${r.reviewPointLabel}'}',
    );

    final checkpoint = r.checkpoint;
    if (checkpoint != null) {
      buf.writeln('checkpoint_taught_scope: ${checkpoint.taughtScope}');
      if (checkpoint.openQuestions.isNotEmpty) {
        buf.writeln(
          'checkpoint_open_questions: '
          '${checkpoint.openQuestions.join(" | ")}',
        );
      }
      if (checkpoint.nextPosition != null) {
        buf.writeln('checkpoint_next_position: ${checkpoint.nextPosition}');
      }
      buf.writeln(
        'checkpoint_updated_at: '
        '${checkpoint.updatedAt.toIso8601String()}',
      );
    }

    // 权威字段：标准答案是否展示、原答时间由 App 记录，不信任模型自报。
    final latest = _latestUserMessage(r.recentMessages);
    if (latest != null) {
      buf.writeln('latest_answer_is_answer_shown: ${latest.isAnswerShown}');
      buf.writeln(
        'latest_answer_created_at: ${latest.createdAt.toIso8601String()}',
      );
    }
    return _section('current_scope', buf.toString().trimRight());
  }

  String _tools(List<ToolContract> tools) {
    if (tools.isEmpty) return '';
    final buf = StringBuffer();
    for (final tool in tools) {
      buf.writeln('- ${tool.name}: ${tool.purpose}');
    }
    return _section('allowed_tools', buf.toString().trimRight());
  }

  CoachMessage? _latestUserMessage(List<CoachMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') return messages[i];
    }
    return null;
  }

  // ── 预算内选取 ────────────────────────────────────────────────────

  _Selection _selectMessages(
    List<CoachMessage> messages,
    int charBudget, {
    required int maxItems,
  }) {
    final kept = <String>[];
    final keptIds = <MessageId>[];
    final seen = <String>{};
    var dropped = 0;
    var duplicates = 0;
    var used = 0;
    var exhausted = false;

    // 从最新往回放；只有预算用尽才停止，保证最近一轮一定在。
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final text = message.content.trim();
      if (text.isEmpty) {
        dropped++;
        continue;
      }
      if (seen.contains(text)) {
        // 重复资料优先压缩，而不是先砍掉最近的真实问答。
        duplicates++;
        dropped++;
        continue;
      }
      final line = _renderMessage(message, text);
      if (exhausted ||
          keptIds.length >= maxItems ||
          used + line.length > charBudget) {
        exhausted = true;
        dropped++;
        continue;
      }
      seen.add(text);
      kept.insert(0, line);
      keptIds.insert(0, message.id);
      used += line.length + 1;
    }

    return _Selection(
      lines: kept,
      keptIds: keptIds,
      dropped: dropped,
      duplicates: duplicates,
    );
  }

  String _renderMessage(CoachMessage m, String text) {
    final shown = m.isAnswerShown ? ' answer_shown=true' : '';
    return '[${m.sequence}][${m.role}][message_id=${m.id}]$shown $text';
  }

  _EvidenceSelection _selectEvidence(
    List<ContextEvidence> evidence,
    int charBudget, {
    required int maxItems,
  }) {
    final lines = <String>[];
    final ids = <String>[];
    var used = 0;
    var dropped = 0;
    for (final item in evidence) {
      if (ids.length >= maxItems) {
        dropped++;
        continue;
      }
      final line = '[${item.citationId}] ${item.title} :: ${item.snippet}';
      if (used + line.length > charBudget) {
        dropped++;
        continue;
      }
      lines.add(line);
      ids.add(item.citationId);
      used += line.length + 1;
    }
    return _EvidenceSelection(lines: lines, citationIds: ids, dropped: dropped);
  }

  String _section(String name, String body) =>
      body.isEmpty ? '' : '## $name\n$body';
}

class _Selection {
  const _Selection({
    required this.lines,
    required this.keptIds,
    required this.dropped,
    required this.duplicates,
  });

  final List<String> lines;
  final List<MessageId> keptIds;
  final int dropped;
  final int duplicates;
}

class _EvidenceSelection {
  const _EvidenceSelection({
    required this.lines,
    required this.citationIds,
    required this.dropped,
  });

  final List<String> lines;
  final List<String> citationIds;
  final int dropped;
}
