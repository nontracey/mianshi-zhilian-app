/// 目标与资料状态（三入口中的「目标与资料」）。
///
/// 职责：把外部材料（岗位 JD、简历、参考文档）导成结构化的本地实体并落库。
/// 解析器由装配层注入；当前应用装配根据 AI 配置切换模型解析，未配置时使用规则解析。
///
/// 导入完成后通过 [onDataChanged] 通知 `CoachProvider` 重载（二者共享同一 [CoachStore]）。
///
/// 文案约定：本层**不持有用户可见文案**，只回传 l10n key 与占位符，
/// 由页面用 `l10n.get/getp` 翻译。
library;

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../coach/domain/common.dart';
import '../coach/domain/goal.dart';
import '../coach/domain/evidence.dart';
import '../coach/domain/knowledge.dart';
import '../coach/domain/resume.dart';
import '../coach/jobs/jd_import_service.dart';
import '../coach/jobs/link_parser.dart';
import '../coach/jobs/models.dart';
import '../coach/jobs/search_service.dart';
import '../coach/knowledge/importer.dart';
import '../coach/knowledge/parser.dart';
import '../coach/knowledge/source.dart';
import '../coach/persistence/coach_store.dart';
import '../coach/persistence/extension_records.dart';
import '../coach/resume/resume_parse.dart';
import '../services/job_search_config.dart';

/// 运行期可变的搜索通道来源（设置改了立刻生效）。
typedef JobSearchServiceProvider = JobDiscoveryService? Function();

/// 通道状态来源，UI 据此区分真实通道 / 演示数据 / 未配置。
typedef JobSearchChannelProvider = JobSearchChannelState? Function();

/// 一次导入的结果摘要（供 UI 展示「做了什么、待确认什么」）。
///
/// 只携带 **l10n key + 参数**，不带用户可见文案：翻译由 UI 层完成
/// （provider 层不持有中文，见 `lib/l10n/check_l10n_keys.py` 契约）。
class ImportOutcome {
  ImportOutcome({
    required this.ok,
    required this.messageKey,
    this.messageParams = const {},
    this.noteKeys = const [],
    this.diagnostics = const [],
    this.createdGoalId,
    this.createdResumeId,
    this.createdSourceId,
    this.requirementCount = 0,
    this.claimCount = 0,
    this.chunkCount = 0,
  });

  final bool ok;

  /// 主文案 key。
  final String messageKey;

  /// 主文案占位符（如 `{'title': '...'}`）。
  final Map<String, dynamic> messageParams;

  /// 附加说明文案 key（顺序展示）。
  final List<String> noteKeys;

  /// 诊断信息（解析器/网络返回的原始说明，按原样展示，便于排错）。
  final List<String> diagnostics;

  final GoalId? createdGoalId;
  final ResumeId? createdResumeId;
  final SourceId? createdSourceId;
  final int requirementCount;
  final int claimCount;
  final int chunkCount;
}

class GoalProvider extends ChangeNotifier {
  GoalProvider({
    required CoachStore store,
    required DocumentImporter documents,
    required ResumeImportService resumeImport,
    required JdImportService jdImport,
    JobDiscoveryService? jobSearch,
    JobSearchServiceProvider? jobSearchProvider,
    JobSearchChannelProvider? channelProvider,
    this.canMutate,
    this.profileId = 'local-default',
  }) : _store = store,
       _documents = documents,
       _resumeImport = resumeImport,
       _jdImport = jdImport,
       _jobSearch = jobSearch,
       _jobSearchProvider = jobSearchProvider,
       _channelProvider = channelProvider;

  final CoachStore _store;
  final DocumentImporter _documents;
  final ResumeImportService _resumeImport;
  final JdImportService _jdImport;

  /// 岗位搜索通道（§6.7）。为 `null` 表示**未配置**——UI 必须如实告知，
  /// 不能把「未配置」显示成「搜到 0 条」。
  ///
  /// 通道会随设置在运行期变化，因此优先读 [jobSearchProvider]（每次现取），
  /// 静态注入的 [jobSearch] 只作为测试与固定装配的兜底。
  final JobDiscoveryService? _jobSearch;
  final JobSearchServiceProvider? _jobSearchProvider;
  final JobSearchChannelProvider? _channelProvider;

  /// 当前通道（每次现取，配置变了立刻生效）。
  JobDiscoveryService? get _currentJobSearch =>
      _jobSearchProvider?.call() ?? _jobSearch;

  /// 是否已配置可用的搜索通道。
  bool get jobSearchConfigured => _currentJobSearch != null;

  /// 当前通道的模式与说明（UI 用它区分「真实通道 / 演示数据 / 未配置」）。
  JobSearchChannelState? get jobSearchChannel => _channelProvider?.call();

  /// 执行一次岗位搜索。未配置时抛错，由 UI 捕获并给出连接入口。
  Future<List<JobCard>> searchJobs(SearchQuery query) async =>
      (await searchJobsResult(query)).cards;

  Future<JobSearchResult> searchJobsResult(SearchQuery query) async {
    final service = _currentJobSearch;
    if (service == null) {
      throw StateError('job search transport is not configured');
    }
    return service.searchResult(query);
  }

  final String profileId;
  final bool Function()? canMutate;

  /// 导入成功后回调（main.dart 里接到 `CoachProvider.reload`）。
  Future<void> Function()? onDataChanged;

  bool _busy = false;
  bool get busy => _busy;

  /// 最近一次导入结果。UI 用它展示「做了什么 / 待确认什么」。
  ImportOutcome? _lastOutcome;
  ImportOutcome? get lastOutcome => _lastOutcome;

  Future<T> _run<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _notifyChanged() async {
    final cb = onDataChanged;
    if (cb != null) await cb();
  }

  /// 记录并广播最近一次导入结果，返回同一对象便于调用处 `return`。
  ImportOutcome _setOutcome(ImportOutcome outcome) {
    _lastOutcome = outcome;
    notifyListeners();
    return outcome;
  }

  ImportOutcome _fail(String key, {Map<String, dynamic> params = const {}}) =>
      ImportOutcome(ok: false, messageKey: key, messageParams: params);

  // ── 岗位 JD ─────────────────────────────────────────────────────────

  /// 从粘贴的 JD 文本建立目标。
  Future<ImportOutcome> importJdFromText(
    String text, {
    String? title,
    JobPlatform? platform,
    String? url,
  }) {
    return _run(() async {
      if (text.trim().isEmpty) {
        return _setOutcome(_fail('coach_import_empty_jd'));
      }
      final result = await _jdImport.importFromText(
        text,
        profileId: profileId,
        title: title,
        platform: platform,
        url: url,
      );
      await _persistJobImport(result);
      final ok = result.status != JobImportStatus.failed;
      final outcome = ok
          ? ImportOutcome(
              ok: true,
              messageKey: 'coach_import_jd_ok',
              messageParams: {
                'title': result.goal.title,
                'count': result.requirements.length,
              },
              noteKeys: const ['coach_import_review_requirements_hint'],
              diagnostics: result.notes,
              createdGoalId: result.goal.id,
              requirementCount: result.requirements.length,
            )
          : _fail('coach_import_jd_failed');
      _setOutcome(outcome);
      if (ok) await _notifyChanged();
      return outcome;
    });
  }

  /// 从岗位链接建立目标：识别平台 → 抓正文 → 解析。
  Future<ImportOutcome> importJdFromUrl(String rawInput) {
    return _run(() async {
      final link = parseJobLink(rawInput);
      if (link == null) {
        return _setOutcome(_fail('coach_import_no_link'));
      }
      final result = await _jdImport.importFromUrl(link, profileId: profileId);
      await _persistJobImport(result);
      final ok = result.status != JobImportStatus.failed;
      final outcome = ok
          ? ImportOutcome(
              ok: true,
              messageKey: 'coach_import_jd_ok',
              messageParams: {
                'title': result.goal.title,
                'count': result.requirements.length,
              },
              noteKeys: [
                if (link.platform == JobPlatform.unknown)
                  'coach_import_unknown_platform_hint',
                'coach_import_review_requirements_hint',
              ],
              diagnostics: result.notes,
              createdGoalId: result.goal.id,
              requirementCount: result.requirements.length,
            )
          : ImportOutcome(
              ok: false,
              messageKey: 'coach_import_jd_url_failed',
              diagnostics: result.notes,
            );
      _setOutcome(outcome);
      if (ok) await _notifyChanged();
      return outcome;
    });
  }

  Future<void> _persistJobImport(JobImportResult result) async {
    if (result.status == JobImportStatus.failed) return;
    await _store.transaction(() async {
      await _store.putGoal(result.goal);
      await _store.putGoalRequirements(result.requirements);
      // Every accepted JD requirement gets an app-owned knowledge identity,
      // one initial review point and an explicit goal link. The title is the
      // JD wording; no model-generated answer or user experience is inserted.
      final now = _jdImport.clock.now();
      for (final requirement in result.requirements) {
        final item = KnowledgeItem(
          id: _jdImport.idGen.next(),
          profileId: profileId,
          title: requirement.title,
          aliases: const [],
          contentStatus: 'ai-draft-unverified',
          createdAt: now,
          updatedAt: now,
        );
        await _store.putKnowledgeItem(item);
        final point = ReviewPoint(
          id: _jdImport.idGen.next(),
          profileId: profileId,
          knowledgeItemId: item.id,
          label: requirement.title,
          createdAt: now,
        );
        await _store.putReviewPoint(point);
        await _store.putReviewState(
          ReviewState(
            reviewPointId: point.id,
            profileId: profileId,
            knowledgeItemId: item.id,
          ),
        );
        await _store.putGoalKnowledgeLink(
          GoalKnowledgeLink(
            goalId: result.goal.id,
            knowledgeItemId: item.id,
            profileId: profileId,
            requirementIds: [requirement.id],
            createdAt: now,
          ),
        );
      }
    });
  }

  /// 删除目标（级联删除其要求与关联）。
  Future<void> deleteGoal(GoalId goalId) async {
    await _run(() async {
      await _store.deleteGoal(goalId);
      _setOutcome(
        ImportOutcome(ok: true, messageKey: 'coach_import_goal_deleted'),
      );
    });
    await _notifyChanged();
  }

  /// Save a user edit to one JD requirement. Edits remain scoped to the
  /// originating goal/profile and do not rewrite the preserved JD source.
  Future<void> updateRequirement(GoalRequirement requirement) async {
    if (requirement.profileId != profileId) {
      throw StateError('Requirement belongs to another profile');
    }
    final goal = await _store.getGoal(requirement.goalId);
    if (goal == null || goal.profileId != profileId) {
      throw StateError('Requirement goal belongs to another profile');
    }
    await _store.transaction(() async {
      final saved = await _store.listGoalRequirements(goal.id);
      if (!saved.any((r) => r.id == requirement.id))
        throw StateError('Requirement no longer exists');
      await _store.putGoalRequirement(requirement);
      final revisions = await _store.listGoalRevisions(
        goal.id,
        profileId: profileId,
      );
      final number =
          revisions.fold<int>(
            0,
            (v, r) => r.revisionNumber > v ? r.revisionNumber : v,
          ) +
          1;
      final now = DateTime.now();
      final rows = (await _store.listGoalRequirements(goal.id))
        ..sort((a, b) => a.id.compareTo(b.id));
      await _store.putGoalRevision(
        GoalRevision(
          id: '${goal.id}.revision.$number',
          goalId: goal.id,
          profileId: profileId,
          revisionNumber: number,
          contentHash: sha256
              .convert(
                utf8.encode(jsonEncode(rows.map((r) => r.toJson()).toList())),
              )
              .toString(),
          createdAt: now,
          note: 'user_requirement_edit',
        ),
      );
      await _store.putGoal(goal.copyWith(updatedAt: now));
    });
    _setOutcome(ImportOutcome(ok: true, messageKey: 'save'));
    await _notifyChanged();
  }

  // ── 简历 ────────────────────────────────────────────────────────────

  /// 导入简历文本；[requirements] 传入时会顺带建立「主张 × 要求」映射。
  Future<ImportOutcome> importResumeFromText(
    String text, {
    String? fileName,
    String? versionLabel,
    List<GoalRequirement> requirements = const [],
  }) {
    return _run(() async {
      if (text.trim().isEmpty) {
        return _setOutcome(_fail('coach_import_empty_resume'));
      }
      final result = await _resumeImport.importText(
        text,
        profileId: profileId,
        fileName: fileName,
        versionLabel: versionLabel,
        requirements: requirements.isEmpty ? null : requirements,
      );
      await _store.transaction(() async {
        await _store.putResume(result.resume);
        for (final p in result.projects) {
          await _store.putProject(p);
        }
        for (final c in result.claims) {
          await _store.putResumeClaim(c);
        }
        for (final l in result.links) {
          await _store.putClaimRequirementLink(l);
        }
        final goalIds = requirements.map((r) => r.goalId).toSet();
        for (final goalId in goalIds) {
          final goal = await _store.getGoal(goalId);
          if (goal?.profileId != profileId) continue;
          await _store.putGoalResumeLink(
            GoalResumeLink(
              goalId: goalId,
              resumeId: result.resume.id,
              profileId: profileId,
              isDefault: true,
              createdAt: result.resume.createdAt,
            ),
          );
        }
      });
      final pending = result.claims
          .where((c) => c.status == ClaimStatus.pending)
          .length;
      final outcome = ImportOutcome(
        ok: true,
        messageKey: 'coach_import_resume_ok',
        messageParams: {
          'projects': result.projects.length,
          'claims': result.claims.length,
        },
        noteKeys: [if (pending > 0) 'coach_import_claims_pending_hint'],
        diagnostics: result.notes,
        createdResumeId: result.resume.id,
        claimCount: result.claims.length,
      );
      _setOutcome(outcome);
      await _notifyChanged();
      return outcome;
    });
  }

  /// Import a PDF/DOCX resume through the same configured document parser as
  /// reference material, then send only extracted text to the resume parser.
  /// Scanned files fail before a Resume is written.
  Future<ImportOutcome> importResumeFromBytes(
    List<int> bytes, {
    String? fileName,
    String? versionLabel,
    List<GoalRequirement> requirements = const [],
  }) {
    return _run(() async {
      try {
        final text = await _documents.extractText(bytes, fileName: fileName);
        // Reuse the text path without toggling busy state a second time.
        final result = await _resumeImport.importText(
          text,
          profileId: profileId,
          fileName: fileName,
          versionLabel: versionLabel,
          requirements: requirements.isEmpty ? null : requirements,
        );
        await _store.transaction(() async {
          await _store.putResume(result.resume);
          for (final p in result.projects) await _store.putProject(p);
          for (final c in result.claims) await _store.putResumeClaim(c);
          for (final l in result.links) await _store.putClaimRequirementLink(l);
          for (final goalId in requirements.map((r) => r.goalId).toSet()) {
            final goal = await _store.getGoal(goalId);
            if (goal?.profileId != profileId) continue;
            await _store.putGoalResumeLink(
              GoalResumeLink(
                goalId: goalId,
                resumeId: result.resume.id,
                profileId: profileId,
                isDefault: true,
                createdAt: result.resume.createdAt,
              ),
            );
          }
        });
        final pending = result.claims
            .where((c) => c.status == ClaimStatus.pending)
            .length;
        final outcome = ImportOutcome(
          ok: true,
          messageKey: 'coach_import_resume_ok',
          messageParams: {
            'projects': result.projects.length,
            'claims': result.claims.length,
          },
          noteKeys: [if (pending > 0) 'coach_import_claims_pending_hint'],
          diagnostics: result.notes,
          createdResumeId: result.resume.id,
          claimCount: result.claims.length,
        );
        _setOutcome(outcome);
        await _notifyChanged();
        return outcome;
      } on ParseException catch (e) {
        return _setOutcome(
          ImportOutcome(
            ok: false,
            messageKey: 'coach_import_parse_failed',
            diagnostics: [e.message],
          ),
        );
      }
    });
  }

  /// 写回一条主张（用户确认/否认后调用）。
  ///
  /// 只更新主张记录本身；**不会**因此把它升级成 Jd/Resume 事实之外的东西——
  /// 已确认主张才允许在提示词里当事实使用（见 `CoachPromptBuilder`）。
  Future<void> updateClaim(ResumeClaim claim) async {
    if (claim.profileId != profileId)
      throw StateError("Claim belongs to another profile");
    await _store.putResumeClaim(claim);
    _setOutcome(
      ImportOutcome(
        ok: true,
        messageKey: claim.isConfirmed
            ? 'coach_import_claim_confirmed'
            : 'coach_import_claim_pending',
      ),
    );
    await _notifyChanged();
  }

  /// 便捷方法：按状态更新一条主张。
  Future<void> setClaimStatus(ResumeClaim claim, ClaimStatus status) {
    if (claim.status == status) return Future.value();
    return updateClaim(
      ResumeClaim(
        id: claim.id,
        profileId: claim.profileId,
        resumeId: claim.resumeId,
        projectId: claim.projectId,
        statement: claim.statement,
        originalSpan: claim.originalSpan,
        status: status,
        confidence: claim.confidence,
      ),
    );
  }

  // ── 参考文档 ────────────────────────────────────────────────────────

  /// 导入参考资料（Markdown / 纯文本 / 粘贴），切块后落库供定向检索使用。
  Future<ImportOutcome> importDocument({
    required String text,
    String? title,
    SourceType type = SourceType.paste,
    String? url,
    KnowledgeItemId? knowledgeItemId,
  }) {
    return _run(() async {
      if (text.trim().isEmpty) {
        return _setOutcome(_fail('coach_import_empty_doc'));
      }
      final result = await _documents.importText(
        ImportRequest(
          text: text,
          title: title,
          type: type,
          url: url,
          profileId: profileId,
          knowledgeItemId: knowledgeItemId,
        ),
      );
      await _store.transaction(() async {
        await _store.putSource(result.source);
        await _store.putSourceChunks(result.chunks);
      });
      final outcome = ImportOutcome(
        ok: true,
        messageKey: 'coach_import_doc_ok',
        messageParams: {
          'title': result.source.title,
          'chunks': result.chunks.length,
        },
        createdSourceId: result.source.id,
        chunkCount: result.chunks.length,
      );
      _setOutcome(outcome);
      await _notifyChanged();
      return outcome;
    });
  }

  /// Replace a source's current text while retaining the previous snapshot
  /// and chunk IDs for old citations. Linked knowledge becomes stale until
  /// reviewed against the revised material.
  Future<ImportOutcome> updateDocumentSource(Source source, String text) {
    return _run(() async {
      if (canMutate?.call() == false) {
        return _setOutcome(_fail('coach_source_busy'));
      }
      if (text.trim().isEmpty)
        return _setOutcome(_fail('coach_import_empty_doc'));
      if (source.profileId != profileId)
        return _setOutcome(_fail('coach_source_update_conflict'));
      if (source.status != IngestionStatus.ready)
        return _setOutcome(_fail('coach_source_update_conflict'));
      var changed = false;
      var chunkCount = 0;
      try {
        await _store.transaction(() async {
          final current = await _store.getSource(source.id);
          if (current == null ||
              current.profileId != profileId ||
              current.revision != source.revision ||
              current.contentHash != source.contentHash) {
            throw StateError('source changed; reload before updating');
          }
          if (current.contentHash == computeContentHash(text) &&
              current.content == text)
            return;
          final oldChunks = await _store.listSourceChunks(current.id);
          final linked = oldChunks
              .map((c) => c.knowledgeItemId)
              .whereType<String>()
              .toSet();
          final result = _documents.reviseText(
            current,
            text,
            knowledgeItemId: linked.length == 1 ? linked.single : null,
          );
          await _store.putExtension(
            CoachExtensionRecord(
              profileId: profileId,
              kind: CoachExtensionKind.sourceRevision,
              id: '${current.id}@${current.revision}',
              revision: 1,
              value: {
                'source': current.toJson(),
                'chunkIds': oldChunks.map((c) => c.id).toList(),
              },
              updatedAt: _documents.clock.now(),
            ),
          );
          await _store.putSource(result.source);
          await _store.putSourceChunks(result.chunks);
          for (final id in linked) {
            final item = await _store.getKnowledgeItem(id);
            if (item != null && item.profileId == profileId) {
              await _store.putKnowledgeItem(
                item.copyWith(
                  contentStatus: 'stale',
                  version: item.version + 1,
                  updatedAt: _documents.clock.now(),
                ),
              );
            }
          }
          changed = true;
          chunkCount = result.chunks.length;
        });
      } on StateError {
        return _setOutcome(_fail('coach_source_update_conflict'));
      }
      if (changed) await _notifyChanged();
      return _setOutcome(
        ImportOutcome(
          ok: true,
          messageKey: changed
              ? 'coach_source_updated'
              : 'coach_source_unchanged',
          messageParams: {'title': source.title, 'chunks': chunkCount},
          createdSourceId: source.id,
          chunkCount: chunkCount,
        ),
      );
    });
  }

  /// 从文件字节导入（PDF/DOCX 依赖平台解析器；未配置时会明确抛错）。
  Future<ImportOutcome> importDocumentBytes(
    List<int> bytes, {
    String? title,
    SourceType type = SourceType.pdf,
  }) {
    return _run(() async {
      try {
        final result = await _documents.importBytes(
          bytes,
          ImportRequest(
            text: '',
            title: title,
            type: type,
            profileId: profileId,
          ),
        );
        await _store.transaction(() async {
          await _store.putSource(result.source);
          await _store.putSourceChunks(result.chunks);
        });
        final outcome = ImportOutcome(
          ok: true,
          messageKey: 'coach_import_doc_ok',
          messageParams: {
            'title': result.source.title,
            'chunks': result.chunks.length,
          },
          createdSourceId: result.source.id,
          chunkCount: result.chunks.length,
        );
        _setOutcome(outcome);
        await _notifyChanged();
        return outcome;
      } on ParseException catch (e) {
        // 解析器未配置：明确失败并附原始原因，不静默返回空文档。
        return _setOutcome(
          ImportOutcome(
            ok: false,
            messageKey: 'coach_import_parse_failed',
            diagnostics: [e.message],
          ),
        );
      }
    });
  }

  void clearOutcome() {
    _lastOutcome = null;
    notifyListeners();
  }
}
