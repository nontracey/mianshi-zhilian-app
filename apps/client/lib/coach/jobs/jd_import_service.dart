/// JD 导入与解析（§6.7）。链接导入与知识检索共用网络/来源基础设施，但业务接口分开：
/// [JobDiscoveryService] 找岗位，[JdImportService] 提取职位要求。
///
/// 优先读取网页已有 JobPosting 结构化数据，再做受约束的模型解析；
/// 结构化数据只是可利用的格式，不保证每个平台都有。
library;

import 'dart:convert';

import '../domain/common.dart';
import '../domain/goal.dart';
import '../knowledge/source.dart';
import '../model/gateway.dart';
import '../model/http_client.dart';
import '../model/messages.dart';
import 'link_parser.dart';
import 'models.dart';

/// 解析出的单条要求草稿。
class RequirementDraft {
  RequirementDraft({
    required this.statement,
    this.type = RequirementType.capability,
    this.importance = Importance.medium,
    this.jdSourceSpan,
    this.inferred = false,
    this.inferenceRationale,
  });

  final String statement;
  final RequirementType type;
  final Importance importance;
  final String? jdSourceSpan;
  final bool inferred;
  final String? inferenceRationale;
}

/// 模型/结构化数据解析出的 JD 结构。
class JdParseResult {
  JdParseResult({
    required this.title,
    this.company,
    this.location,
    this.salaryText,
    this.description,
    required this.requirements,
  });

  final String title;
  final String? company;
  final String? location;
  final String? salaryText;
  final String? description;
  final List<RequirementDraft> requirements;
}

/// JD 解析器：把 JD 文本/结构化数据转成 [JdParseResult]。
abstract class JdParser {
  Future<JdParseResult> parse(String text, {String? url, String? title});
}

/// 无模型时的确定性兜底解析器。
///
/// 不调用模型、不推断语义：按行拆分，把「看起来像要求在列」的行转成草稿。
/// 明确不是「智能解析」——产出的要求一律标 `inferred: true`，由用户逐条确认或删除。
/// 目的是让未配置模型的用户也能走通导入流程，而不是静默失败。
class HeuristicJdParser implements JdParser {
  const HeuristicJdParser({this.maxRequirements = 30});

  final int maxRequirements;

  /// 常见「要求」段落起始标记。
  static final RegExp _sectionStart = RegExp(
    r'^(任职要求|岗位要求|职位要求|技能要求|任职资格|要求|我们期待|加分项)',
  );

  /// 常见「非要求」段落起始标记（命中则停止收集）。
  static final RegExp _sectionStop = RegExp(
    r'^(岗位职责|工作内容|职位描述|岗位描述|公司介绍|团队介绍|福利|薪资|关于我们|工作地点)',
  );

  static final RegExp _bullet = RegExp(
    r'^\s*(?:[-*·•●○▪]|\d+[.、)）]|[（(]\d+[)）])\s*',
  );

  static final RegExp _knownTitle = RegExp(r'^(岗位名称|职位名称|职位|岗位)[：:]\s*(.+)$');

  @override
  Future<JdParseResult> parse(String text, {String? url, String? title}) async {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? detectedTitle;
    final requirements = <RequirementDraft>[];
    var insideRequirements = false;
    // 命中「岗位职责/公司介绍」等段落说明已离开要求段：之后的项目符号不再收集，
    // 直到再次遇到「任职要求」类标题（例如 JD 先写职责、后写要求）。
    var stopped = false;
    var sawRequirementHeader = false;

    for (final line in lines) {
      final titleMatch = _knownTitle.firstMatch(line);
      if (titleMatch != null && detectedTitle == null) {
        detectedTitle = titleMatch.group(2)!.trim();
        continue;
      }

      if (_sectionStop.hasMatch(line)) {
        insideRequirements = false;
        stopped = true;
        continue;
      }
      if (_sectionStart.hasMatch(line)) {
        insideRequirements = true;
        stopped = false;
        sawRequirementHeader = true;
        continue;
      }

      final bullet = _bullet.hasMatch(line);
      // 在「任职要求」段内，或（尚未进入其它段落时的）项目符号行，都视作候选要求。
      if (!insideRequirements && !(bullet && !stopped)) continue;

      final statement = line.replaceFirst(_bullet, '').trim();
      if (statement.length < 2) continue;
      if (requirements.length >= maxRequirements) break;

      requirements.add(
        RequirementDraft(
          statement: statement,
          importance: _guessImportance(statement),
          inferred: true,
          inferenceRationale: sawRequirementHeader
              ? '来自任职要求段落，未做语义判断，待用户确认'
              : '按项目符号行拆分，未做语义判断，待用户确认',
        ),
      );
    }

    return JdParseResult(
      title: detectedTitle ?? title ?? '未命名岗位',
      description: text.length > 4000 ? text.substring(0, 4000) : text,
      requirements: requirements,
    );
  }

  Importance _guessImportance(String statement) {
    if (RegExp(r'精通|深入|必须|必需|要求\d+年|熟练掌握').hasMatch(statement)) {
      return Importance.high;
    }
    if (RegExp(r'优先|加分|了解|熟悉者|有.*经验者优先').hasMatch(statement)) {
      return Importance.low;
    }
    return Importance.medium;
  }
}

/// 基于模型的结构化 JD 解析器（受约束 JSON 提案；模型只建议，ID 由 App 分配）。
class ModelJdParser implements JdParser {
  ModelJdParser(this.gateway, {this.responseFormatJson = true});
  final ModelGateway gateway;
  final bool responseFormatJson;

  @override
  Future<JdParseResult> parse(String text, {String? url, String? title}) async {
    final prompt = _buildPrompt(text);
    final resp = await gateway.complete(
      ModelGatewayRequest(
        messages: [ChatMessage.system(_systemPrompt), ChatMessage.user(prompt)],
        responseFormatJson: responseFormatJson,
        timeoutMs: 60000,
      ),
    );
    return _parseJson(resp.message.content, title: title);
  }

  JdParseResult _parseJson(String content, {String? title}) {
    final cleaned = _extractJson(content);
    final json = jsonDecode(cleaned) as Map<String, dynamic>;
    final reqs = (json['requirements'] as List<dynamic>? ?? [])
        .map((e) => _toDraft(e as Map<String, dynamic>))
        .toList();
    return JdParseResult(
      title: (json['title'] as String?) ?? title ?? '未命名岗位',
      company: json['company'] as String?,
      location: json['location'] as String?,
      salaryText: json['salaryText'] as String?,
      description: json['description'] as String?,
      requirements: reqs,
    );
  }

  RequirementDraft _toDraft(Map<String, dynamic> m) {
    return RequirementDraft(
      statement: (m['statement'] as String?) ?? '',
      type: _typeFrom(m['type'] as String?),
      importance: _importanceFrom(m['importance'] as String?),
      jdSourceSpan: m['jdSourceSpan'] as String?,
      inferred: m['inferred'] as bool? ?? false,
      inferenceRationale: m['inferenceRationale'] as String?,
    );
  }

  RequirementType _typeFrom(String? v) {
    return RequirementType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => RequirementType.capability,
    );
  }

  Importance _importanceFrom(String? v) {
    return Importance.values.firstWhere(
      (e) => e.name == v,
      orElse: () => Importance.medium,
    );
  }
}

/// 页面正文抓取器（注入式）。
abstract class JdFetcher {
  Future<String> fetchText(String url, {CancelToken? cancel});
}

/// JD 导入服务：链接或文本 -> 目标 JD + 能力要求清单 + 提取状态。
class JdImportService {
  JdImportService({
    required this.fetcher,
    required this.parser,
    required this.idGen,
    required this.clock,
  });

  final JdFetcher fetcher;
  final JdParser parser;
  final IdGenerator idGen;
  final Clock clock;

  /// 从链接导入：抓取正文 -> 尝试结构化数据 -> 受约束模型解析 -> 构建目标。
  Future<JobImportResult> importFromUrl(
    ParsedJobLink link, {
    required ProfileId profileId,
  }) async {
    String text;
    try {
      text = await fetcher.fetchText(link.url);
    } on HttpCanceledException {
      rethrow;
    } catch (e) {
      return JobImportResult(
        goal: _emptyGoal(profileId, link.url, link.platform),
        requirements: const [],
        status: JobImportStatus.failed,
        notes: ['抓取失败：$e'],
      );
    }
    final sub = await importFromText(
      text,
      profileId: profileId,
      url: link.url,
      platform: link.platform,
      externalJobId: link.externalJobId,
    );
    if (text.trim().isEmpty) {
      return JobImportResult(
        goal: sub.goal,
        requirements: sub.requirements,
        status: JobImportStatus.takenDown,
        notes: [...sub.notes, '正文为空，岗位可能已下架'],
      );
    }
    return sub;
  }

  /// 从文本导入：受约束模型解析 -> 构建目标与要求。
  Future<JobImportResult> importFromText(
    String text, {
    required ProfileId profileId,
    String? title,
    JobPlatform? platform,
    String? url,
    String? externalJobId,
  }) async {
    final hash = computeContentHash(text);
    final now = clock.now();
    JdParseResult parsed;
    final notes = <String>[];
    try {
      parsed = await parser.parse(text, url: url, title: title);
    } catch (e) {
      return JobImportResult(
        goal: _emptyGoal(
          profileId,
          url,
          platform,
          contentHash: hash,
          originalText: text,
        ),
        requirements: const [],
        status: JobImportStatus.failed,
        notes: ['解析失败：$e'],
      );
    }
    if (parsed.requirements.isEmpty) {
      notes.add('未解析出可训练要求；建议用户补充或手动编辑');
    }
    final goal = Goal(
      id: idGen.next(),
      profileId: profileId,
      title: parsed.title,
      originalText: text,
      originalUrl: url,
      canonicalUrl: url,
      platform: platform?.toStorage(),
      externalJobId: externalJobId,
      company: parsed.company,
      location: parsed.location,
      salaryText: parsed.salaryText,
      description: parsed.description,
      extractionStatus: 'complete',
      contentHash: hash,
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final requirements = parsed.requirements.map((d) {
      return GoalRequirement(
        id: idGen.next(),
        goalId: goal.id,
        profileId: profileId,
        type: d.type,
        title: d.statement,
        jdSourceSpan: d.jdSourceSpan,
        importance: d.importance,
        inferred: d.inferred,
        inferenceRationale: d.inferenceRationale,
        createdAt: now,
      );
    }).toList();

    return JobImportResult(
      goal: goal,
      requirements: requirements,
      status: notes.isEmpty
          ? JobImportStatus.complete
          : JobImportStatus.partial,
      notes: notes,
    );
  }

  Goal _emptyGoal(
    ProfileId profileId,
    String? url,
    JobPlatform? platform, {
    String? contentHash,
    String? originalText,
  }) {
    final now = clock.now();
    return Goal(
      id: idGen.next(),
      profileId: profileId,
      title: '导入失败的岗位',
      originalText: originalText ?? '',
      originalUrl: url,
      canonicalUrl: url,
      platform: platform?.toStorage(),
      extractionStatus: 'failed',
      contentHash: contentHash ?? computeContentHash(originalText ?? url ?? ''),
      active: false,
      createdAt: now,
      updatedAt: now,
    );
  }
}

String _buildPrompt(String jdText) =>
    '请将以下岗位 JD 解析为 JSON。字段：title、company、location、salaryText、'
    'description、requirements（数组，每项含 statement/type/importance/jdSourceSpan/'
    'inferred）。type 取值：responsibility/hardRequirement/niceToHave/capability；'
    'importance 取值 low/medium/high；jdSourceSpan 为 JD 原句片段（如能定位）。\n\n'
    'JD 正文：\n$jdText';

const _systemPrompt = '你是岗位解析助手，只输出 JSON，不解释。明确写出的要求与推断分开标注。';

String _extractJson(String content) {
  final trimmed = content.trim();
  final fence = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return fence?.group(1)?.trim() ?? trimmed;
}
