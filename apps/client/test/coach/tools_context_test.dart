/// 内部工具契约与上下文构建单测（§7.4、§7.5、§8.3）。
///
/// 全部纯 Dart、不连网、不依赖 Flutter。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/context/context_builder.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/tools/tool_contract.dart';

Future<void> main() async {
  final catalog = const ToolCatalog();
  final authorizer = const ToolAuthorizer();

  CoachMessage msg(
    String id,
    String role,
    String content, {
    int sequence = 1,
    bool isAnswerShown = false,
  }) => CoachMessage(
    id: id,
    sessionId: 's1',
    profileId: 'p1',
    role: role,
    content: content,
    turnId: 't1',
    sequence: sequence,
    createdAt: DateTime(2026, 9, 11),
    isAnswerShown: isAnswerShown,
  );

  group('工具契约与白名单（§7.5）', () {
    test('训练循环默认只开放 8 个业务工具', () {
      expect(catalog.loopTools().length, 8);
    });

    test('岗位/导入工具不在训练循环范围', () {
      final names = catalog.loopTools().map((c) => c.name).toSet();
      expect(names.contains(ToolNames.searchJobs), isFalse);
      expect(names.contains(ToolNames.importJd), isFalse);
      expect(names.contains(ToolNames.importResume), isFalse);
    });

    test('未登记的工具直接拒绝，不做尽力执行', () {
      final result = authorizer.authorize(
        const ToolInvocation(callId: 'c1', name: 'shell_exec'),
        context: const ToolAccessContext(),
      );
      expect(result.allowed, isFalse);
      expect(result.code, ToolDenialCode.unknownTool);
    });

    test('范围未开放时拒绝（默认不许搜索岗位）', () {
      final result = authorizer.authorize(
        const ToolInvocation(
          callId: 'c1',
          name: ToolNames.searchJobs,
          args: {'query': 'java'},
        ),
        context: const ToolAccessContext(),
      );
      expect(result.allowed, isFalse);
      expect(result.code, ToolDenialCode.scopeNotOpen);
    });

    test('参数缺失或未知一律拒绝', () {
      final missing = authorizer.authorize(
        const ToolInvocation(callId: 'c1', name: ToolNames.searchKnowledge),
        context: const ToolAccessContext(),
      );
      expect(missing.code, ToolDenialCode.invalidArgs);

      final unknown = authorizer.authorize(
        const ToolInvocation(
          callId: 'c2',
          name: ToolNames.searchKnowledge,
          args: {'query': 'java', 'where': 'all'},
        ),
        context: const ToolAccessContext(),
      );
      expect(unknown.code, ToolDenialCode.invalidArgs);
    });

    test('超过单轮调用上限后拒绝', () {
      final result = authorizer.authorize(
        const ToolInvocation(callId: 'c1', name: ToolNames.getCoachState),
        context: const ToolAccessContext(turnCallCount: 6),
      );
      expect(result.allowed, isFalse);
      expect(result.code, ToolDenialCode.budgetExhausted);
    });
  });

  group('破坏性操作必须带 UI 确认令牌（§7.5、§6.8）', () {
    test('模型自称“用户已同意”不构成授权：无令牌必须拒绝', () {
      final result = authorizer.authorize(
        const ToolInvocation(
          callId: 'c1',
          name: ToolNames.commitGoalDeletion,
          args: {
            'operationId': 'op-1',
            'selectedIds': <String>[],
            // 模型只能在文本里说“用户已同意”，这里没有任何令牌。
          },
        ),
        context: const ToolAccessContext(
          openScopes: {ToolScope.trainingLoop, ToolScope.destructive},
        ),
      );
      expect(result.allowed, isFalse);
      expect(result.code, ToolDenialCode.missingConfirmationToken);
    });

    test('令牌 operationId 与请求不一致时拒绝（防跨操作复用）', () {
      final result = authorizer.authorize(
        ToolInvocation(
          callId: 'c1',
          name: ToolNames.commitGoalDeletion,
          args: const {'operationId': 'op-2', 'selectedIds': <String>[]},
          confirmationToken: ConfirmationToken(
            operationId: 'op-1',
            issuedAt: DateTime(2026, 9, 11),
            subject: 'goal-1',
          ),
        ),
        context: const ToolAccessContext(
          openScopes: {ToolScope.trainingLoop, ToolScope.destructive},
        ),
      );
      expect(result.allowed, isFalse);
      expect(result.code, ToolDenialCode.staleConfirmationToken);
    });

    test('带匹配令牌且范围开放时才允许提交', () {
      final result = authorizer.authorize(
        ToolInvocation(
          callId: 'c1',
          name: ToolNames.commitGoalDeletion,
          args: const {'operationId': 'op-1', 'selectedIds': <String>[]},
          confirmationToken: ConfirmationToken(
            operationId: 'op-1',
            issuedAt: DateTime(2026, 9, 11),
            subject: 'goal-1',
          ),
        ),
        context: const ToolAccessContext(
          openScopes: {ToolScope.trainingLoop, ToolScope.destructive},
        ),
      );
      expect(result.allowed, isTrue);
      expect(result.contract?.name, ToolNames.commitGoalDeletion);
    });

    test('preview 不需要令牌，但 commit 需要', () {
      expect(
        catalog
            .byName(ToolNames.previewGoalDeletion)
            ?.requiresConfirmationToken,
        isFalse,
      );
      expect(
        catalog.byName(ToolNames.commitGoalDeletion)?.requiresConfirmationToken,
        isTrue,
      );
    });
  });

  group('调用留痕与结果体积（§8.3）', () {
    test('参数摘要脱敏密钥字段并截断', () {
      final summary = summarizeToolArgs(const {
        'query': 'java',
        'apiKey': 'sk-super-secret',
        'token': 'abc',
      });
      expect(summary.contains('sk-super-secret'), isFalse);
      expect(summary.contains('<redacted>'), isTrue);
      expect(summary.contains('query=java'), isTrue);
    });

    test('超长结果必须截断，不整包进上下文', () {
      final ledger = ToolLoopLedger();
      final contract = catalog.byName(ToolNames.searchKnowledge)!;
      final long = 'x' * (contract.maxResultChars! + 500);
      final clamped = ledger.clampResult(contract, long);
      expect(clamped.length < long.length, isTrue);
      expect(clamped.contains('[truncated'), isTrue);
    });

    test('账本按单轮上限累计并暴露给下一轮授权', () {
      final ledger = ToolLoopLedger();
      for (var i = 0; i < 6; i++) {
        ledger.record(
          ToolCallRecord(
            callId: 'c$i',
            name: ToolNames.getCoachState,
            argsSummary: '',
            status: ToolCallStatus.ok,
            at: DateTime(2026, 9, 11),
          ),
        );
      }
      expect(ledger.exhausted, isTrue);
      expect(ledger.canCall(), isFalse);
      expect(ledger.contextFor({ToolScope.trainingLoop}).turnCallCount, 6);
    });
  });

  group('上下文六段与预算压缩（§7.4）', () {
    const builder = ContextBuilder();

    test('六个部分齐全，且只带与本题关联的片段', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.review,
          rules: 'RULES_BODY',
          goalId: 'g1',
          goalRevision: 3,
          resumeId: 'r1',
          resumeRevision: 2,
          projectIds: const ['proj-1'],
          requirements: const [
            ContextRequirement(
              id: 'req-1',
              title: '接口幂等',
              importance: Importance.high,
            ),
          ],
          claims: const [
            ContextClaim(
              id: 'cl-1',
              statement: '负责订单重复提交处理',
              status: ClaimStatus.confirmed,
              projectId: 'proj-1',
            ),
          ],
          projects: const [ContextProject(id: 'proj-1', name: '订单系统')],
          knowledgeItemId: 'k1',
          knowledgeTitle: '幂等设计',
          reviewPointId: 'rp1',
          reviewPointLabel: '去重依据',
          allowedTools: catalog.loopTools(),
        ),
      );

      expect(ctx.rulesSection.contains('RULES_BODY'), isTrue);
      expect(ctx.selectionSection.contains('review'), isTrue);
      expect(ctx.selectionSection.contains('req-1'), isTrue);
      expect(ctx.selectionSection.contains('cl-1'), isTrue);
      expect(ctx.selectionSection.contains('proj-1'), isTrue);
      expect(ctx.scopeSection.contains('幂等设计'), isTrue);
      // 关联片段之外的实体不应出现：只断言没有其它 requirement。
      expect(ctx.selectionSection.contains('req-2'), isFalse);
      expect(ctx.toolsSection.contains(ToolNames.searchKnowledge), isTrue);
      expect(ctx.toolsSection.contains(ToolNames.searchJobs), isFalse);
    });

    test('权威字段来自结构化存储：isAnswerShown 由 App 决定', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.review,
          rules: 'R',
          recentMessages: [
            msg('m1', 'assistant', 'Q1'),
            msg('m2', 'user', '我的原答', sequence: 2, isAnswerShown: true),
          ],
        ),
      );
      expect(
        ctx.scopeSection.contains('latest_answer_is_answer_shown: true'),
        isTrue,
      );
    });

    test('checkpoint 的已讲范围与疑问进入范围段', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.learning,
          rules: 'R',
          checkpoint: LessonCheckpoint(
            id: 'cp1',
            sessionId: 's1',
            profileId: 'p1',
            knowledgeItemId: 'k1',
            taughtScope: 'JDK8 尾插法',
            openQuestions: const ['并发扩容边界'],
            nextPosition: 'section-3',
            createdAt: DateTime(2026, 9, 11),
            updatedAt: DateTime(2026, 9, 11),
          ),
        ),
      );
      expect(ctx.scopeSection.contains('JDK8 尾插法'), isTrue);
      expect(ctx.scopeSection.contains('并发扩容边界'), isTrue);
      expect(ctx.scopeSection.contains('section-3'), isTrue);
    });

    test(
      'large project selections stay inside the total budget and expose real message IDs',
      () {
        final ctx = builder.build(
          ContextRequest(
            profileId: 'p1',
            mode: SessionMode.interview,
            rules: 'R',
            projects: [
              for (var i = 0; i < 50; i++)
                ContextProject(
                  id: 'p$i',
                  name: 'Project $i',
                  originalSpan: 'original ' * 150,
                ),
            ],
            recentMessages: [
              msg('real-answer-id', 'user', 'My original answer', sequence: 1),
            ],
          ),
        );
        expect(ctx.usedChars, lessThanOrEqualTo(ctx.availableChars));
        expect(ctx.truncated, true);
        expect(ctx.recentQaSection, contains('message_id=real-answer-id'));
        expect(ctx.recentQaSection, contains('My original answer'));
        expect(ctx.selectionSection, contains('selection truncated'));
      },
    );

    test('重复资料被合并压缩，而不是先砍掉最近真实问答', () {
      final repeated = 'REPEATED_NOTE ' * 4;
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.learning,
          rules: 'R',
          recentMessages: [
            msg('m1', 'user', repeated, sequence: 1),
            msg('m2', 'assistant', repeated, sequence: 2),
            msg('m3', 'user', 'LATEST_REAL_ANSWER', sequence: 3),
          ],
        ),
      );
      expect(ctx.duplicateMessageCount, 1);
      expect(ctx.recentQaSection.contains('LATEST_REAL_ANSWER'), isTrue);
    });

    test('预算不足时丢弃较早消息，但最近一轮一定保留', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.review,
          rules: 'R',
          recentMessages: [
            msg('m1', 'user', 'FIRST_OLD_MESSAGE ' * 5, sequence: 1),
            msg('m2', 'assistant', 'SECOND ' * 20, sequence: 2),
            msg('m3', 'user', 'LATEST_ANSWER', sequence: 3),
          ],
          budget: const ContextBudget(
            maxChars: 900,
            reserveForOutputChars: 100,
            reserveForToolChars: 100,
          ),
        ),
      );
      expect(ctx.recentQaSection.contains('LATEST_ANSWER'), isTrue);
      expect(ctx.recentQaSection.contains('FIRST_OLD_MESSAGE'), isFalse);
      expect(ctx.droppedMessageCount >= 1, isTrue);
    });

    test('证据优先于历史问答，引用 ID 可核对', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.learning,
          rules: 'R',
          recentMessages: [msg('m1', 'user', 'CHATTER ' * 30, sequence: 1)],
          evidence: const [
            ContextEvidence(
              citationId: 'cite-1',
              title: '幂等键',
              snippet: '以业务唯一键去重',
            ),
            ContextEvidence(
              citationId: 'cite-2',
              title: '重试窗口',
              snippet: '失败重试窗口内需幂等',
            ),
          ],
          budget: const ContextBudget(
            maxChars: 1200,
            reserveForOutputChars: 100,
            reserveForToolChars: 100,
          ),
        ),
      );
      expect(ctx.citationIds.length, 2);
      expect(ctx.evidenceSection.contains('cite-1'), isTrue);
      expect(ctx.evidenceSection.contains('cite-2'), isTrue);
    });

    test('证据超出条数上限时被截断并计数', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.learning,
          rules: 'R',
          evidence: [
            for (var i = 0; i < 12; i++)
              ContextEvidence(
                citationId: 'cite-$i',
                title: 't$i',
                snippet: 's$i',
              ),
          ],
          budget: const ContextBudget(maxEvidenceItems: 3),
        ),
      );
      expect(ctx.citationIds.length, 3);
      expect(ctx.droppedEvidenceCount, 9);
    });

    test('不整包发送历史：keptMessageIds 受 maxRecentMessages 限制', () {
      final ctx = builder.build(
        ContextRequest(
          profileId: 'p1',
          mode: SessionMode.learning,
          rules: 'R',
          recentMessages: [
            for (var i = 0; i < 30; i++)
              msg(
                'm$i',
                i.isEven ? 'user' : 'assistant',
                'msg-body-$i',
                sequence: i,
              ),
          ],
          budget: const ContextBudget(maxRecentMessages: 4),
        ),
      );
      expect(ctx.keptMessageIds.length <= 4, isTrue);
      expect(ctx.droppedMessageCount >= 26, isTrue);
    });
  });
}
