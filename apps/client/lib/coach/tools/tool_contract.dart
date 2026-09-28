/// 内部工具契约、参数校验与权限层（§7.5、§8.3）。
///
/// 设计要点：
/// - 训练循环默认只暴露 8 个业务工具；岗位检索、导入与工作流编辑走独立领域服务，
///   不在每轮出题时全部开放。
/// - 破坏性操作必须 `preview` → `commit` 分离：`commit` 需要 UI 签发的确认令牌，
///   模型在文本里声称“用户已同意”不构成授权。
/// - 每次调用都留痕（callId / 参数摘要 / 状态 / 结果引用），便于审计与复现。
/// - 外部 MCP 经适配后共享同一套调用日志与权限层，但**不能**直接获得数据库写入、
///   成绩设置或任意命令执行能力。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';

/// 稳定工具标识。这些是协议名，不是用户可见文案。
abstract final class ToolNames {
  // ── 训练循环（默认开放）────────────────────────────────────────────
  static const String getCoachState = 'get_coach_state';
  static const String searchKnowledge = 'search_knowledge';
  static const String readSource = 'read_source';
  static const String proposeKnowledgeCard = 'propose_knowledge_card';
  static const String saveLessonCheckpoint = 'save_lesson_checkpoint';
  static const String proposeAssessment = 'propose_assessment';
  static const String requestPlanChange = 'request_plan_change';
  static const String finishSession = 'finish_session';

  // ── 仅在用户搜索/导入意图下开放 ────────────────────────────────────
  static const String searchJobs = 'search_jobs';
  static const String importJd = 'import_jd';
  static const String importResume = 'import_resume';

  // ── 破坏性/变更类：preview 与 commit 分离 ──────────────────────────
  static const String previewGoalDeletion = 'preview_goal_deletion';
  static const String commitGoalDeletion = 'commit_goal_deletion';
  static const String proposeWorkflowChange = 'propose_workflow_change';
}

/// 工具开放范围。范围决定“什么时候才允许被调用”，与模型是否有意愿无关。
enum ToolScope {
  /// 每轮出题都可用的业务工具。
  trainingLoop,

  /// 只有用户明确表达搜索/导入意图时才开放，并进入结果预览。
  userIntent,

  /// 破坏性或长期偏好变更。commit 必须携带 UI 确认令牌。
  destructive,
}

/// 工具参数类型。
enum ToolArgType { string, integer, boolean, stringList, json }

/// 单个参数规格。
class ToolArgSpec {
  const ToolArgSpec({required this.name, required this.type});

  final String name;
  final ToolArgType type;

  bool accepts(Object? value) {
    switch (type) {
      case ToolArgType.string:
        return value is String;
      case ToolArgType.integer:
        return value is int;
      case ToolArgType.boolean:
        return value is bool;
      case ToolArgType.stringList:
        return value is List && value.every((e) => e is String);
      case ToolArgType.json:
        return value is Map || value is List;
    }
  }
}

/// 工具契约。
///
/// [purpose] 是给开发者/日志看的英文说明，**不是** UI 文案；用户可见说明由页面按
/// l10n key 渲染，避免纯 Dart 层持有用户文案。
class ToolContract {
  const ToolContract({
    required this.name,
    required this.scope,
    required this.purpose,
    this.requiredArgs = const [],
    this.optionalArgs = const [],
    this.requiresConfirmationToken = false,
    this.maxResultChars,
  });

  final String name;
  final ToolScope scope;
  final String purpose;
  final List<ToolArgSpec> requiredArgs;
  final List<ToolArgSpec> optionalArgs;

  /// `commit_*` 类工具为 true：必须带 UI 签发的 [ConfirmationToken]。
  final bool requiresConfirmationToken;

  /// 结果体积上限（字符）。超长结果必须截断并标注，不能整包塞进上下文。
  final int? maxResultChars;

  List<ToolArgSpec> get allArgs => [...requiredArgs, ...optionalArgs];

  /// 参数校验。返回空列表表示通过。
  List<String> validateArgs(Map<String, dynamic> args) {
    final errors = <String>[];
    for (final spec in requiredArgs) {
      if (!args.containsKey(spec.name) || args[spec.name] == null) {
        errors.add('missing required arg: ${spec.name}');
        continue;
      }
      if (!spec.accepts(args[spec.name])) {
        errors.add('arg ${spec.name} expects ${spec.type.name}');
      }
    }
    for (final spec in optionalArgs) {
      final value = args[spec.name];
      if (value == null) continue;
      if (!spec.accepts(value)) {
        errors.add('arg ${spec.name} expects ${spec.type.name}');
      }
    }
    final known = {for (final s in allArgs) s.name};
    for (final key in args.keys) {
      if (!known.contains(key)) errors.add('unknown arg: $key');
    }
    return errors;
  }
}

/// 工具目录：白名单。未知工具一律拒绝，不做“尽力而为”的猜测执行。
class ToolCatalog {
  const ToolCatalog();

  static const ToolContract _getCoachState = ToolContract(
    name: ToolNames.getCoachState,
    scope: ToolScope.trainingLoop,
    purpose: 'read goals, mode, progress and current plan summary',
  );

  static const ToolContract _searchKnowledge = ToolContract(
    name: ToolNames.searchKnowledge,
    scope: ToolScope.trainingLoop,
    purpose: 'search only the currently allowed sources, return citation ids',
    requiredArgs: [ToolArgSpec(name: 'query', type: ToolArgType.string)],
    optionalArgs: [ToolArgSpec(name: 'topK', type: ToolArgType.integer)],
    maxResultChars: 4000,
  );

  static const ToolContract _readSource = ToolContract(
    name: ToolNames.readSource,
    scope: ToolScope.trainingLoop,
    purpose: 'read a bounded body by source/chunk id; not a file reader',
    requiredArgs: [ToolArgSpec(name: 'chunkId', type: ToolArgType.string)],
    maxResultChars: 6000,
  );

  static const ToolContract _proposeKnowledgeCard = ToolContract(
    name: ToolNames.proposeKnowledgeCard,
    scope: ToolScope.trainingLoop,
    purpose:
        'submit a cited knowledge draft; service validates sources before storing',
    requiredArgs: [
      ToolArgSpec(name: 'title', type: ToolArgType.string),
      ToolArgSpec(name: 'citations', type: ToolArgType.stringList),
    ],
    optionalArgs: [ToolArgSpec(name: 'body', type: ToolArgType.string)],
    maxResultChars: 2000,
  );

  static const ToolContract _saveLessonCheckpoint = ToolContract(
    name: ToolNames.saveLessonCheckpoint,
    scope: ToolScope.trainingLoop,
    purpose:
        'save taught scope and open questions; records no assessment result',
    requiredArgs: [
      ToolArgSpec(name: 'knowledgeItemId', type: ToolArgType.string),
      ToolArgSpec(name: 'taughtScope', type: ToolArgType.string),
    ],
    optionalArgs: [
      ToolArgSpec(name: 'openQuestions', type: ToolArgType.stringList),
      ToolArgSpec(name: 'nextPosition', type: ToolArgType.string),
    ],
  );

  static const ToolContract _proposeAssessment = ToolContract(
    name: ToolNames.proposeAssessment,
    scope: ToolScope.trainingLoop,
    purpose:
        'point at an existing question and answer, submit dimensions and rationale',
    requiredArgs: [
      ToolArgSpec(name: 'reviewPointId', type: ToolArgType.string),
      ToolArgSpec(name: 'questionMessageId', type: ToolArgType.string),
      ToolArgSpec(name: 'answerMessageIds', type: ToolArgType.stringList),
      ToolArgSpec(name: 'dimensions', type: ToolArgType.json),
    ],
  );

  static const ToolContract _requestPlanChange = ToolContract(
    name: ToolNames.requestPlanChange,
    scope: ToolScope.trainingLoop,
    purpose:
        'propose a load/mode/extra-batch change; the scheduler computes the plan',
    requiredArgs: [ToolArgSpec(name: 'proposal', type: ToolArgType.json)],
  );

  static const ToolContract _finishSession = ToolContract(
    name: ToolNames.finishSession,
    scope: ToolScope.trainingLoop,
    purpose:
        'build report and leftovers from real records; no arbitrary pass rate',
  );

  static const ToolContract _searchJobs = ToolContract(
    name: ToolNames.searchJobs,
    scope: ToolScope.userIntent,
    purpose:
        'search postings through a configured channel; returns cards for review',
    requiredArgs: [ToolArgSpec(name: 'query', type: ToolArgType.string)],
    maxResultChars: 4000,
  );

  static const ToolContract _importJd = ToolContract(
    name: ToolNames.importJd,
    scope: ToolScope.userIntent,
    purpose: 'import a JD by link or text and enter result preview',
    optionalArgs: [
      ToolArgSpec(name: 'url', type: ToolArgType.string),
      ToolArgSpec(name: 'text', type: ToolArgType.string),
    ],
    maxResultChars: 4000,
  );

  static const ToolContract _importResume = ToolContract(
    name: ToolNames.importResume,
    scope: ToolScope.userIntent,
    purpose: 'import a resume document and enter claim review',
    optionalArgs: [
      ToolArgSpec(name: 'text', type: ToolArgType.string),
      ToolArgSpec(name: 'fileName', type: ToolArgType.string),
    ],
    maxResultChars: 4000,
  );

  static const ToolContract _previewGoalDeletion = ToolContract(
    name: ToolNames.previewGoalDeletion,
    scope: ToolScope.destructive,
    purpose: 'compute deletion impact; no mutation happens here',
    requiredArgs: [ToolArgSpec(name: 'goalIds', type: ToolArgType.stringList)],
    maxResultChars: 6000,
  );

  static const ToolContract _commitGoalDeletion = ToolContract(
    name: ToolNames.commitGoalDeletion,
    scope: ToolScope.destructive,
    purpose:
        'apply a previewed deletion; re-checks references inside a transaction',
    requiredArgs: [
      ToolArgSpec(name: 'operationId', type: ToolArgType.string),
      ToolArgSpec(name: 'selectedIds', type: ToolArgType.stringList),
    ],
    requiresConfirmationToken: true,
  );

  static const ToolContract _proposeWorkflowChange = ToolContract(
    name: ToolNames.proposeWorkflowChange,
    scope: ToolScope.destructive,
    purpose: 'produce a bounded change draft; applied by the same PlanService',
    requiredArgs: [ToolArgSpec(name: 'change', type: ToolArgType.json)],
  );

  /// 全部契约。
  static const List<ToolContract> all = [
    _getCoachState,
    _searchKnowledge,
    _readSource,
    _proposeKnowledgeCard,
    _saveLessonCheckpoint,
    _proposeAssessment,
    _requestPlanChange,
    _finishSession,
    _searchJobs,
    _importJd,
    _importResume,
    _previewGoalDeletion,
    _commitGoalDeletion,
    _proposeWorkflowChange,
  ];

  /// 训练循环默认开放的 8 个业务工具（§7.5）。
  List<ToolContract> loopTools() =>
      all.where((c) => c.scope == ToolScope.trainingLoop).toList();

  /// 某个范围下的全部工具。
  List<ToolContract> forScope(ToolScope scope) =>
      all.where((c) => c.scope == scope).toList();

  ToolContract? byName(String name) {
    for (final contract in all) {
      if (contract.name == name) return contract;
    }
    return null;
  }

  bool isKnown(String name) => byName(name) != null;
}

/// 确认令牌的有效期。
///
/// 破坏性操作（删除 JD 及其关联知识、学习记录）不能凭一张永久有效的令牌提交：
/// 预览页挂机数小时后，用户看到的内容与提交时的事实可能已经不同。
abstract final class ConfirmationTtl {
  static const Duration deletion = Duration(minutes: 15);
}

/// UI 侧签发的确认令牌。
///
/// 只有用户在界面上真正点击确认后，UI 才会创建并传入；模型在文本里声称“用户已
/// 同意”不构成授权（§7.5、§6.8）。
class ConfirmationToken {
  const ConfirmationToken({
    required this.operationId,
    required this.issuedAt,
    required this.subject,
    this.expectedRevisions = const {},
    this.ttl = ConfirmationTtl.deletion,
  });

  /// 与 `preview` 返回的 operationId 一致，防止跨操作复用令牌。
  final String operationId;
  final DateTime issuedAt;

  /// 确认对象标识（如 goalId 或 claimId）。
  final String subject;

  /// 预览时观察到的版本号；提交时若不一致则拒绝，必须刷新预览。
  final Map<String, String> expectedRevisions;

  /// 令牌有效期。过期后必须重新预览并重新确认。
  final Duration ttl;

  /// 令牌是否已过期。提交方必须传入"现在"，否则无从判断新鲜度。
  bool isExpired(DateTime now) => now.difference(issuedAt) > ttl;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'issuedAt': issuedAt.toIso8601String(),
    'subject': subject,
    'expectedRevisions': expectedRevisions,
  };
}

/// 一次工具调用请求。
class ToolInvocation {
  const ToolInvocation({
    required this.callId,
    required this.name,
    this.args = const {},
    this.confirmationToken,
  });

  final String callId;
  final String name;
  final Map<String, dynamic> args;
  final ConfirmationToken? confirmationToken;
}

/// 授权上下文：当前开放了哪些范围、本轮已调用几次。
class ToolAccessContext {
  const ToolAccessContext({
    this.openScopes = const {ToolScope.trainingLoop},
    this.turnCallCount = 0,
    this.maxCallsPerTurn = maxToolCallsPerTurn,
  });

  final Set<ToolScope> openScopes;
  final int turnCallCount;
  final int maxCallsPerTurn;
}

/// 拒绝原因码（协议值，非 UI 文案）。
abstract final class ToolDenialCode {
  static const String unknownTool = 'unknown_tool';
  static const String scopeNotOpen = 'scope_not_open';
  static const String invalidArgs = 'invalid_args';
  static const String missingConfirmationToken = 'missing_confirmation_token';
  static const String staleConfirmationToken = 'stale_confirmation_token';
  static const String budgetExhausted = 'budget_exhausted';
}

/// 授权结果。
class ToolAuthorization {
  const ToolAuthorization.allow(ToolContract this.contract)
    : code = null,
      detail = null;

  const ToolAuthorization.deny(String this.code, String this.detail)
    : contract = null;

  final ToolContract? contract;
  final String? code;
  final String? detail;

  bool get allowed => contract != null;
}

/// 权限层。所有工具调用都必须先经过它。
class ToolAuthorizer {
  const ToolAuthorizer({this.catalog = const ToolCatalog()});

  final ToolCatalog catalog;

  ToolAuthorization authorize(
    ToolInvocation invocation, {
    required ToolAccessContext context,
  }) {
    if (context.turnCallCount >= context.maxCallsPerTurn) {
      return const ToolAuthorization.deny(
        ToolDenialCode.budgetExhausted,
        'tool call budget for this turn is used up',
      );
    }

    final contract = catalog.byName(invocation.name);
    if (contract == null) {
      return ToolAuthorization.deny(
        ToolDenialCode.unknownTool,
        'not in whitelist: ${invocation.name}',
      );
    }

    if (!context.openScopes.contains(contract.scope)) {
      return ToolAuthorization.deny(
        ToolDenialCode.scopeNotOpen,
        'scope ${contract.scope.name} is not open in this turn',
      );
    }

    final argErrors = contract.validateArgs(invocation.args);
    if (argErrors.isNotEmpty) {
      return ToolAuthorization.deny(
        ToolDenialCode.invalidArgs,
        argErrors.join('; '),
      );
    }

    if (contract.requiresConfirmationToken) {
      final token = invocation.confirmationToken;
      if (token == null) {
        // 模型自称“用户已同意”不能替代 UI 令牌。
        return const ToolAuthorization.deny(
          ToolDenialCode.missingConfirmationToken,
          'requires a token issued by the UI after an explicit user confirmation',
        );
      }
      final operationId = invocation.args['operationId'];
      if (operationId is String && operationId != token.operationId) {
        return ToolAuthorization.deny(
          ToolDenialCode.staleConfirmationToken,
          'token operationId does not match the requested operation',
        );
      }
    }

    return ToolAuthorization.allow(contract);
  }
}

/// 调用状态。
enum ToolCallStatus { ok, denied, failed, skipped }

/// 调用留痕。`resultRef` 只存引用（如 chunkId / messageId），不整包复制结果正文。
class ToolCallRecord {
  const ToolCallRecord({
    required this.callId,
    required this.name,
    required this.argsSummary,
    required this.status,
    this.resultRef,
    this.errorCode,
    this.at,
  });

  final String callId;
  final String name;
  final String argsSummary;
  final ToolCallStatus status;
  final String? resultRef;
  final String? errorCode;
  final DateTime? at;

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'name': name,
    'argsSummary': argsSummary,
    'status': status.name,
    if (resultRef != null) 'resultRef': resultRef,
    if (errorCode != null) 'errorCode': errorCode,
    if (at != null) 'at': at!.toIso8601String(),
  };
}

/// 参数摘要：截断 + 脱敏。
///
/// 外部返回或用户粘贴的内容可能包含密钥字段；日志只保留结构与长度，
/// 不落敏感值（§8.3）。
String summarizeToolArgs(
  Map<String, dynamic> args, {
  int maxChars = 240,
  Set<String> sensitiveKeys = const {
    'apikey',
    'api_key',
    'token',
    'password',
    'secret',
    'authorization',
  },
}) {
  final parts = <String>[];
  for (final entry in args.entries) {
    final key = entry.key;
    if (sensitiveKeys.contains(key.toLowerCase())) {
      parts.add('$key=<redacted>');
      continue;
    }
    final value = entry.value;
    final text = value is String ? value : value.toString();
    final clipped = text.length <= 60
        ? text
        : '${text.substring(0, 60)}...(${text.length})';
    parts.add('$key=$clipped');
  }
  final joined = parts.join(', ');
  return joined.length <= maxChars
      ? joined
      : '${joined.substring(0, maxChars)}...';
}

/// 单轮工具循环账本：限制调用次数与预算，并保留可审计记录。
class ToolLoopLedger {
  ToolLoopLedger({
    this.maxCallsPerTurn = maxToolCallsPerTurn,
    this.perToolTimeout = const Duration(seconds: 20),
    this.turnBudget = const Duration(seconds: 90),
  });

  final int maxCallsPerTurn;
  final Duration perToolTimeout;
  final Duration turnBudget;

  final List<ToolCallRecord> _records = [];

  List<ToolCallRecord> get records => List.unmodifiable(_records);

  int get callCount => _records.length;

  bool get exhausted => _records.length >= maxCallsPerTurn;

  /// 还能不能再发起一次调用。
  bool canCall() => !exhausted;

  void record(ToolCallRecord record) {
    _records.add(record);
  }

  /// 供下一轮授权的上下文。
  ToolAccessContext contextFor(Set<ToolScope> openScopes) => ToolAccessContext(
    openScopes: openScopes,
    turnCallCount: _records.length,
    maxCallsPerTurn: maxCallsPerTurn,
  );

  /// 结果是否必须截断（超长结果不得整包进上下文）。
  String clampResult(ToolContract contract, String result) {
    final limit = contract.maxResultChars;
    if (limit == null || result.length <= limit) return result;
    return '${result.substring(0, limit)}\n[truncated ${result.length - limit} chars]';
  }
}
