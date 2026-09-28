/// 简历解析与主张确认（§6.9）。上传文件 -> 本地解析文字 -> 提取项目与主张草稿
/// -> 展示原文对照 -> 用户修正并选定简历版本。信息未写明留“待确认”，
/// 不能从目标 JD 补成已做事实。
library;

import 'dart:convert';

import '../domain/common.dart';
import '../domain/goal.dart';
import '../domain/resume.dart';
import '../model/gateway.dart';
import '../model/messages.dart';
import 'claim_mapping.dart';

/// 解析出的简历字段（技能陈述、目标岗位、年限等）。
class ResumeFields {
  ResumeFields({
    this.skills,
    this.summary,
    this.targetRole,
    this.experienceYears,
  });
  final String? skills;
  final String? summary;
  final String? targetRole;
  final int? experienceYears;

  Map<String, dynamic> toJson() => {
    'skills': skills,
    'summary': summary,
    'targetRole': targetRole,
    'experienceYears': experienceYears,
  };
}

/// 项目草稿（本人经历，不是 JD 要求）。
class ProjectDraft {
  ProjectDraft({
    required this.name,
    this.originalSpan,
    this.goal,
    this.responsibilities,
    this.techStack,
    this.metrics,
    this.timeRange,
  });

  final String name;
  final String? originalSpan;
  final String? goal;
  final String? responsibilities;
  final String? techStack;
  final String? metrics;
  final String? timeRange;
}

/// 主张草稿（技能/项目事实/指标等）。
class ClaimDraft {
  ClaimDraft({
    required this.statement,
    this.originalSpan,
    this.projectName,
    this.confidence,
    this.type,
  });

  final String statement;
  final String? originalSpan;

  /// 关联项目名（用于映射到 [Project]）。
  final String? projectName;
  final double? confidence;
  final String? type;
}

/// 解析结果。
class ResumeParseResult {
  ResumeParseResult({
    required this.fields,
    required this.projects,
    required this.claims,
    this.parseNotes = const [],
  });

  final ResumeFields fields;
  final List<ProjectDraft> projects;
  final List<ClaimDraft> claims;
  final List<String> parseNotes;
}

/// 简历解析器：把简历文本转成 [ResumeParseResult]。
abstract class ResumeParser {
  Future<ResumeParseResult> parse(String text, {String? fileName});
}

/// 基于模型的结构化简历解析（受约束 JSON；提取置信度不等于经历可信度）。
class ModelResumeParser implements ResumeParser {
  ModelResumeParser(this.gateway, {this.responseFormatJson = true});
  final ModelGateway gateway;
  final bool responseFormatJson;

  @override
  Future<ResumeParseResult> parse(String text, {String? fileName}) async {
    final resp = await gateway.complete(
      ModelGatewayRequest(
        messages: [
          ChatMessage.system(_systemPrompt),
          ChatMessage.user('$_userPrompt\n\n简历正文：\n$text'),
        ],
        responseFormatJson: responseFormatJson,
        timeoutMs: 60000,
      ),
    );
    return _parseJson(resp.message.content);
  }

  ResumeParseResult _parseJson(String content) {
    final json = jsonDecode(_extractJson(content)) as Map<String, dynamic>;
    final fieldsJson = json['fields'] as Map<String, dynamic>? ?? {};
    final projects = (json['projects'] as List<dynamic>? ?? [])
        .map((e) => _project(e as Map<String, dynamic>))
        .toList();
    final claims = (json['claims'] as List<dynamic>? ?? [])
        .map((e) => _claim(e as Map<String, dynamic>))
        .toList();
    return ResumeParseResult(
      fields: ResumeFields(
        skills: fieldsJson['skills'] as String?,
        summary: fieldsJson['summary'] as String?,
        targetRole: fieldsJson['targetRole'] as String?,
        experienceYears: fieldsJson['experienceYears'] as int?,
      ),
      projects: projects,
      claims: claims,
    );
  }

  ProjectDraft _project(Map<String, dynamic> m) => ProjectDraft(
    name: m['name'] as String? ?? 'coach_resume_unnamed_project',
    originalSpan: m['originalSpan'] as String?,
    goal: m['goal'] as String?,
    responsibilities: m['responsibilities'] as String?,
    techStack: m['techStack'] as String?,
    metrics: m['metrics'] as String?,
    timeRange: m['timeRange'] as String?,
  );

  ClaimDraft _claim(Map<String, dynamic> m) => ClaimDraft(
    statement: m['statement'] as String? ?? '',
    originalSpan: m['originalSpan'] as String?,
    projectName: m['projectName'] as String?,
    confidence: (m['confidence'] as num?)?.toDouble(),
    type: m['type'] as String?,
  );
}

/// 确定性规则解析器：按“项目/经历”标题切块，逐条作为主张（无模型时可用）。
class RuleBasedResumeParser implements ResumeParser {
  const RuleBasedResumeParser();

  @override
  Future<ResumeParseResult> parse(String text, {String? fileName}) async {
    final lines = text.split(RegExp(r'\r?\n'));
    final projects = <ProjectDraft>[];
    final claims = <ClaimDraft>[];
    var currentProject = _BufferProject();

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final isProjectHeader = RegExp(
        r'^(项目|经历|experience|project)',
        caseSensitive: false,
      ).hasMatch(line);
      if (isProjectHeader && currentProject.name != null) {
        projects.add(currentProject.build());
        currentProject = _BufferProject();
      }
      if (isProjectHeader) {
        currentProject.name = line.replaceAll(RegExp(r'[:：]'), '').trim();
        continue;
      }
      if (RegExp(r'^[-•·*]|\d+[.、]').hasMatch(line)) {
        final stmt = line
            .replaceFirst(RegExp(r'^[-•·*]|\d+[.、]\s*'), '')
            .trim();
        claims.add(
          ClaimDraft(
            statement: stmt,
            originalSpan: raw.trim(),
            projectName: currentProject.name,
          ),
        );
      } else if (currentProject.name == null) {
        claims.add(ClaimDraft(statement: line, originalSpan: raw.trim()));
      } else {
        currentProject.responsibilities =
            (currentProject.responsibilities == null
                ? ''
                : '${currentProject.responsibilities}\n') +
            line;
      }
    }
    if (currentProject.name != null) projects.add(currentProject.build());
    return ResumeParseResult(
      fields: ResumeFields(),
      projects: projects,
      claims: claims,
      parseNotes: const ['规则解析为离线兜底，建议用户对照原文校对'],
    );
  }
}

class _BufferProject {
  String? name;
  String? responsibilities;
  ProjectDraft build() => ProjectDraft(
    name: name ?? 'coach_resume_unnamed_project',
    responsibilities: responsibilities,
    originalSpan: name,
  );
}

/// 简历导入服务：文本 -> [Resume] + [Project] + [ResumeClaim] + 可选与 JD 的映射。
class ResumeImportService {
  ResumeImportService({
    required this.parser,
    required this.idGen,
    required this.clock,
    this.matcher,
  });

  final ResumeParser parser;
  final IdGenerator idGen;
  final Clock clock;
  final ClaimMatcher? matcher;

  Future<ResumeImportResult> importText(
    String text, {
    required ProfileId profileId,
    String? fileName,
    String? versionLabel,
    List<GoalRequirement>? requirements,
  }) async {
    final parsed = await parser.parse(text, fileName: fileName);
    final now = clock.now();

    final resume = Resume(
      id: idGen.next(),
      profileId: profileId,
      versionLabel: versionLabel ?? 'v1',
      originalText: text,
      fileName: fileName,
      parsedAt: now,
      createdAt: now,
    );

    final projectByName = <String, Project>{};
    final projects = <Project>[];
    for (final p in parsed.projects) {
      final project = Project(
        id: idGen.next(),
        profileId: profileId,
        resumeId: resume.id,
        name: p.name,
        originalSpan: p.originalSpan,
        goal: p.goal,
        responsibilities: p.responsibilities,
        techStack: p.techStack,
        metrics: p.metrics,
        timeRange: p.timeRange,
      );
      projects.add(project);
      projectByName[p.name] = project;
    }

    final claims = <ResumeClaim>[];
    for (final c in parsed.claims) {
      final projectId = c.projectName == null
          ? null
          : projectByName[c.projectName]?.id;
      claims.add(
        ResumeClaim(
          id: idGen.next(),
          profileId: profileId,
          resumeId: resume.id,
          projectId: projectId,
          statement: c.statement,
          originalSpan: c.originalSpan,
          status: ClaimStatus.pending,
          confidence: c.confidence,
        ),
      );
    }

    List<ClaimRequirementLink> links = [];
    if (requirements != null && matcher != null && claims.isNotEmpty) {
      final drafts = await matcher!.match(
        claimStatements: claims.map((c) => c.statement).toList(),
        requirements: requirements,
      );
      links = drafts.map((d) {
        final claimId = d.claimIndex >= 0 ? claims[d.claimIndex].id : '';
        return ClaimRequirementLink(
          claimId: claimId,
          requirementId: d.requirementId,
          profileId: profileId,
          mappingType: d.mappingType,
          rationale: d.rationale,
        );
      }).toList();
    }

    return ResumeImportResult(
      resume: resume,
      projects: projects,
      claims: claims,
      links: links,
      notes: parsed.parseNotes,
    );
  }
}

/// 简历导入结果。
class ResumeImportResult {
  ResumeImportResult({
    required this.resume,
    required this.projects,
    required this.claims,
    this.links = const [],
    this.notes = const [],
  });

  final Resume resume;
  final List<Project> projects;
  final List<ResumeClaim> claims;
  final List<ClaimRequirementLink> links;
  final List<String> notes;
}

const _systemPrompt =
    '你是简历解析助手，只输出 JSON，不解释。'
    '每个项目与主张保留可回原文的字段 originalSpan。';

String _userPrompt =
    '请解析简历为 JSON：fields(skills/summary/targetRole/'
    'experienceYears)、projects(name/goal/responsibilities/techStack/metrics/'
    'timeRange/originalSpan)、claims(statement/projectName/confidence/type/originalSpan)。'
    '信息未写明时留空，不要编造。';

String _extractJson(String content) {
  final trimmed = content.trim();
  final fence = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return fence?.group(1)?.trim() ?? trimmed;
}
