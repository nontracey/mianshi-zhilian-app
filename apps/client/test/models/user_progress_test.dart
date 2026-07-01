import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';

void main() {
  group('TopicProgress', () {
    final now = DateTime(2025, 6, 8, 10, 0, 0);
    final future = DateTime(2025, 6, 15, 10, 0, 0);

    test('round-trip with all fields filled', () {
      final original = TopicProgress(
        topicId: 'topic-1',
        score: 85,
        status: 'mastered',
        practiceCount: 5,
        lastPracticeAt: now,
        nextReviewAt: future,
      );
      final json = original.toJson();
      final restored = TopicProgress.fromJson(json);
      expect(restored.topicId, 'topic-1');
      expect(restored.score, 85);
      expect(restored.status, 'mastered');
      expect(restored.practiceCount, 5);
      expect(restored.lastPracticeAt, now);
      expect(restored.nextReviewAt, future);
    });

    test('round-trip with nullable fields null', () {
      final original = TopicProgress(
        topicId: 'topic-2',
        score: 42,
        status: 'learning',
      );
      final json = original.toJson();
      final restored = TopicProgress.fromJson(json);
      expect(restored.topicId, 'topic-2');
      expect(restored.score, 42);
      expect(restored.status, 'learning');
      expect(restored.practiceCount, 0);
      expect(restored.lastPracticeAt, isNull);
      expect(restored.nextReviewAt, isNull);
    });

    test('round-trip with status = new', () {
      final original = TopicProgress(
        topicId: 'topic-3',
        score: 0,
        status: 'new',
        practiceCount: 0,
      );
      final restored = TopicProgress.fromJson(original.toJson());
      expect(restored.status, 'new');
      expect(restored.score, 0);
      expect(restored.practiceCount, 0);
    });

    test('round-trip with status = learning', () {
      final original = TopicProgress(
        topicId: 'topic-4',
        score: 50,
        status: 'learning',
        practiceCount: 3,
      );
      final restored = TopicProgress.fromJson(original.toJson());
      expect(restored.status, 'learning');
    });

    test('copyWith creates modified copy', () {
      final original = TopicProgress(
        topicId: 'topic-1',
        score: 50,
        status: 'learning',
        practiceCount: 2,
      );
      final modified = original.copyWith(
        score: 90,
        status: 'mastered',
        practiceCount: 5,
      );
      expect(modified.topicId, 'topic-1');
      expect(modified.score, 90);
      expect(modified.status, 'mastered');
      expect(modified.practiceCount, 5);
      expect(modified.lastPracticeAt, isNull);
      expect(modified.nextReviewAt, isNull);
    });

    test('copyWith with null leaves fields unchanged', () {
      final original = TopicProgress(
        topicId: 'topic-1',
        score: 50,
        status: 'learning',
        practiceCount: 2,
        lastPracticeAt: now,
      );
      final modified = original.copyWith();
      expect(modified.topicId, 'topic-1');
      expect(modified.score, 50);
      expect(modified.status, 'learning');
      expect(modified.lastPracticeAt, now);
    });

    test('fromJson with score as double does not crash', () {
      final json = {'topicId': 't1', 'score': 80.5, 'status': 'mastered'};
      final restored = TopicProgress.fromJson(json);
      expect(restored.score, 80);
    });

    test('fromJson missing practiceCount defaults to 0', () {
      final json = {'topicId': 't1', 'score': 100, 'status': 'new'};
      final restored = TopicProgress.fromJson(json);
      expect(restored.practiceCount, 0);
    });
  });

  group('PracticeSession', () {
    final now = DateTime(2025, 6, 8, 10, 0, 0);
    final later = DateTime(2025, 6, 8, 11, 30, 0);

    test('round-trip with all fields filled', () {
      final original = PracticeSession(
        id: 'session-1',
        topicId: 'topic-1',
        startedAt: now,
        completedAt: later,
        score: 78,
        feedback: 'Good progress, review JVM memory model.',
      );
      final restored = PracticeSession.fromJson(original.toJson());
      expect(restored.id, 'session-1');
      expect(restored.topicId, 'topic-1');
      expect(restored.startedAt, now);
      expect(restored.completedAt, later);
      expect(restored.score, 78);
      expect(restored.feedback, 'Good progress, review JVM memory model.');
    });

    test('round-trip with nullable fields null', () {
      final original = PracticeSession(
        id: 'session-2',
        topicId: 'topic-2',
        startedAt: now,
        score: 0,
      );
      final restored = PracticeSession.fromJson(original.toJson());
      expect(restored.id, 'session-2');
      expect(restored.completedAt, isNull);
      expect(restored.feedback, isNull);
      expect(restored.score, 0);
    });

    test('round-trip with score 100', () {
      final original = PracticeSession(
        id: 'session-3',
        topicId: 'topic-3',
        startedAt: now,
        score: 100,
        feedback: 'Perfect!',
      );
      final restored = PracticeSession.fromJson(original.toJson());
      expect(restored.score, 100);
      expect(restored.feedback, 'Perfect!');
    });
  });

  group('PracticeAttempt', () {
    final now = DateTime(2025, 6, 8, 10, 0, 0);

    test('round-trip with all fields filled', () {
      final original = PracticeAttempt(
        id: 'attempt-1',
        topicId: 'topic-1',
        promptId: 'prompt-1',
        mode: 'recall',
        question: 'What is JVM?',
        answer: 'Java Virtual Machine',
        createdAt: now,
        score: 90,
        level: 'advanced',
        summary: 'Understood JVM basics well.',
        missedPoints: ['garbage collection details'],
        wrongPoints: ['classloader hierarchy'],
        errorTags: ['jvm'],
        improvedAnswer: 'Java Virtual Machine executes bytecode...',
        nextAction: 'review_gc',
        aiConfigId: 'ai-gpt-4',
        aiEvaluated: true,
        localOnly: false,
        analysisStatus: 'success',
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.id, 'attempt-1');
      expect(restored.topicId, 'topic-1');
      expect(restored.promptId, 'prompt-1');
      expect(restored.mode, 'recall');
      expect(restored.question, 'What is JVM?');
      expect(restored.answer, 'Java Virtual Machine');
      expect(restored.createdAt, now);
      expect(restored.score, 90);
      expect(restored.level, 'advanced');
      expect(restored.summary, 'Understood JVM basics well.');
      expect(restored.missedPoints, ['garbage collection details']);
      expect(restored.wrongPoints, ['classloader hierarchy']);
      expect(restored.errorTags, ['jvm']);
      expect(
        restored.improvedAnswer,
        'Java Virtual Machine executes bytecode...',
      );
      expect(restored.nextAction, 'review_gc');
      expect(restored.aiConfigId, 'ai-gpt-4');
      expect(restored.aiEvaluated, true);
      expect(restored.localOnly, false);
      expect(restored.analysisStatus, 'success');
    });

    test('round-trip with nullable fields null and empty lists', () {
      final original = PracticeAttempt(
        id: 'attempt-2',
        topicId: 'topic-2',
        mode: 'review',
        question: 'Explain polymorphism',
        answer: 'Poly means many...',
        createdAt: now,
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.id, 'attempt-2');
      expect(restored.promptId, '');
      expect(restored.mode, 'review');
      expect(restored.score, isNull);
      expect(restored.level, isNull);
      expect(restored.summary, isNull);
      expect(restored.missedPoints, []);
      expect(restored.wrongPoints, []);
      expect(restored.errorTags, []);
      expect(restored.improvedAnswer, isNull);
      expect(restored.nextAction, isNull);
      expect(restored.aiConfigId, isNull);
      expect(restored.aiEvaluated, false);
      expect(restored.localOnly, true);
      expect(restored.analysisStatus, 'unanalysed');
    });

    test('round-trip with mode = mockInterview', () {
      final original = PracticeAttempt(
        id: 'attempt-3',
        topicId: 'topic-3',
        mode: 'mockInterview',
        question: 'Design a rate limiter',
        answer: 'Sliding window...',
        createdAt: now,
        score: 75,
        aiEvaluated: true,
        analysisStatus: 'success',
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.mode, 'mockInterview');
      expect(restored.analysisStatus, 'success');
    });

    test('round-trip with mode = code and analysisStatus = failed', () {
      final original = PracticeAttempt(
        id: 'attempt-4',
        topicId: 'topic-4',
        mode: 'code',
        question: 'Write a binary search',
        answer: 'int binarySearch(...)',
        createdAt: now,
        analysisStatus: 'failed',
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.mode, 'code');
      expect(restored.analysisStatus, 'failed');
    });

    test('round-trip with analysisStatus = pending', () {
      final original = PracticeAttempt(
        id: 'attempt-5',
        topicId: 'topic-5',
        mode: 'recall',
        question: 'What is SOLID?',
        answer: 'SRP, OCP, LSP, ISP, DIP',
        createdAt: now,
        analysisStatus: 'pending',
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.analysisStatus, 'pending');
    });

    test('round-trip with list fields populated', () {
      final original = PracticeAttempt(
        id: 'attempt-6',
        topicId: 'topic-6',
        mode: 'review',
        question: 'Q',
        answer: 'A',
        createdAt: now,
        missedPoints: ['a', 'b', 'c'],
        wrongPoints: ['d', 'e'],
        errorTags: ['tag1', 'tag2'],
      );
      final restored = PracticeAttempt.fromJson(original.toJson());
      expect(restored.missedPoints, ['a', 'b', 'c']);
      expect(restored.wrongPoints, ['d', 'e']);
      expect(restored.errorTags, ['tag1', 'tag2']);
    });

    test('fromJson missing fields use defaults', () {
      final json = {
        'id': 'a1',
        'topicId': 't1',
        'mode': 'review',
        'question': 'Q?',
        'answer': 'A.',
        'createdAt': '2025-06-08T10:00:00.000',
      };
      final restored = PracticeAttempt.fromJson(json);
      expect(restored.promptId, '');
      expect(restored.localOnly, true);
      expect(restored.aiEvaluated, false);
      expect(restored.analysisStatus, 'unanalysed');
      expect(restored.missedPoints, []);
      expect(restored.wrongPoints, []);
      expect(restored.errorTags, []);
    });
  });

  group('MockInterviewSession', () {
    final now = DateTime(2025, 6, 8, 10, 0, 0);
    final later = DateTime(2025, 6, 8, 11, 0, 0);
    final attempt = PracticeAttempt(
      id: 'a1',
      topicId: 't1',
      mode: 'mockInterview',
      question: 'What is JVM?',
      answer: 'Java Virtual Machine',
      createdAt: now,
      score: 80,
      aiEvaluated: true,
      analysisStatus: 'success',
    );

    test('round-trip with all fields filled', () {
      final original = MockInterviewSession(
        id: 'mock-1',
        scenario: 'java-basics',
        startedAt: now,
        completedAt: later,
        topicIds: ['t1', 't2'],
        attempts: [attempt],
        averageScore: 80,
        reportSummary: 'Strong on JVM, weak on GC.',
        weakTopicIds: ['t2'],
        nextActions: ['review_gc'],
        formalMode: true,
      );
      final restored = MockInterviewSession.fromJson(original.toJson());
      expect(restored.id, 'mock-1');
      expect(restored.scenario, 'java-basics');
      expect(restored.startedAt, now);
      expect(restored.completedAt, later);
      expect(restored.topicIds, ['t1', 't2']);
      expect(restored.attempts, hasLength(1));
      expect(restored.attempts[0].id, 'a1');
      expect(restored.attempts[0].score, 80);
      expect(restored.averageScore, 80);
      expect(restored.reportSummary, 'Strong on JVM, weak on GC.');
      expect(restored.weakTopicIds, ['t2']);
      expect(restored.nextActions, ['review_gc']);
      expect(restored.formalMode, true);
    });

    test('round-trip with empty defaults', () {
      final original = MockInterviewSession(
        id: 'mock-2',
        scenario: 'mixed',
        startedAt: now,
      );
      final restored = MockInterviewSession.fromJson(original.toJson());
      expect(restored.id, 'mock-2');
      expect(restored.scenario, 'mixed');
      expect(restored.completedAt, isNull);
      expect(restored.topicIds, []);
      expect(restored.attempts, []);
      expect(restored.averageScore, 0);
      expect(restored.reportSummary, '');
      expect(restored.weakTopicIds, []);
      expect(restored.nextActions, []);
      expect(restored.formalMode, false);
    });

    test('round-trip with multiple nested attempts', () {
      final a2 = PracticeAttempt(
        id: 'a2',
        topicId: 't2',
        mode: 'mockInterview',
        question: 'What is GC?',
        answer: 'Garbage Collection',
        createdAt: now,
        score: 60,
        analysisStatus: 'unanalysed',
      );
      final original = MockInterviewSession(
        id: 'mock-3',
        scenario: 'full-stack',
        startedAt: now,
        attempts: [attempt, a2],
        averageScore: 70,
      );
      final restored = MockInterviewSession.fromJson(original.toJson());
      expect(restored.attempts, hasLength(2));
      expect(restored.attempts[0].id, 'a1');
      expect(restored.attempts[1].id, 'a2');
      expect(restored.averageScore, 70);
    });

    test('fromJson missing scenario defaults to mixed', () {
      final json = {'id': 'mock-4', 'startedAt': '2025-06-08T10:00:00.000'};
      final restored = MockInterviewSession.fromJson(json);
      expect(restored.scenario, 'mixed');
    });
  });

  group('LocalProfile', () {
    test('round-trip with all fields filled', () {
      final original = const LocalProfile(
        nickname: '测试用户',
        avatarSeed: 'seed123',
        avatarUrl: 'https://example.com/avatar.png',
        email: 'user@example.com',
        emailBound: true,
        wechatBound: true,
      );
      final restored = LocalProfile.fromJson(original.toJson());
      expect(restored.nickname, '测试用户');
      expect(restored.avatarSeed, 'seed123');
      expect(restored.avatarUrl, 'https://example.com/avatar.png');
      expect(restored.email, 'user@example.com');
      expect(restored.emailBound, true);
      expect(restored.wechatBound, true);
    });

    test('round-trip with avatarUrl null (omitted from json)', () {
      final original = const LocalProfile(
        nickname: '匿名用户',
        avatarSeed: 'guest_42',
        email: '',
        emailBound: false,
        wechatBound: false,
      );
      final json = original.toJson();
      expect(json.containsKey('avatarUrl'), false);
      final restored = LocalProfile.fromJson(json);
      expect(restored.avatarUrl, isNull);
      expect(restored.nickname, '匿名用户');
      expect(restored.avatarSeed, 'guest_42');
      expect(restored.emailBound, false);
      expect(restored.wechatBound, false);
    });

    test('round-trip with default constructor values', () {
      final original = const LocalProfile();
      final restored = LocalProfile.fromJson(original.toJson());
      expect(restored.nickname, '本地用户');
      expect(restored.avatarSeed, 'local');
      expect(restored.avatarUrl, isNull);
      expect(restored.email, '');
      expect(restored.emailBound, false);
      expect(restored.wechatBound, false);
    });

    test('fromJson missing fields use defaults', () {
      final json = <String, dynamic>{};
      final restored = LocalProfile.fromJson(json);
      expect(restored.nickname, '本地用户');
      expect(restored.email, '');
      expect(restored.emailBound, false);
      expect(restored.wechatBound, false);
    });

    test('copyWith creates modified copy', () {
      final original = const LocalProfile(
        nickname: 'old',
        avatarSeed: 'old_seed',
      );
      final modified = original.copyWith(nickname: 'new', emailBound: true);
      expect(modified.nickname, 'new');
      expect(modified.avatarSeed, 'old_seed');
      expect(modified.emailBound, true);
      expect(modified.wechatBound, false);
    });
  });

  group('SyncSettings', () {
    final now = DateTime(2025, 6, 8, 10, 0, 0);

    test('round-trip with default (local) method', () {
      final original = const SyncSettings();
      final restored = SyncSettings.fromJson(original.toJson());
      expect(restored.method, 'local');
      expect(restored.autoSyncEnabled, true);
      expect(restored.autoSyncIntervalMinutes, 5);
      expect(restored.lastSyncAt, isNull);
      expect(restored.lastSyncStatus, 'local_mode');
      expect(restored.webDavUrl, '');
      expect(restored.githubToken, '');
      expect(restored.giteeToken, '');
      expect(restored.syncPrivatePrepData, true);
      expect(restored.syncAiConfigMetadata, false);
    });

    test('round-trip with webdav method', () {
      final original = const SyncSettings(
        method: 'webdav',
        webDavUrl: 'https://dav.example.com',
        webDavUsername: 'user',
        webDavPassword: 'pass',
        autoSyncEnabled: true,
        autoSyncIntervalMinutes: 15,
        lastSyncStatus: 'success',
      );
      final restored = SyncSettings.fromJson(original.toJson());
      expect(restored.method, 'webdav');
      expect(restored.webDavUrl, 'https://dav.example.com');
      expect(restored.webDavUsername, 'user');
      expect(restored.webDavPassword, 'pass');
      expect(restored.autoSyncIntervalMinutes, 15);
      expect(restored.lastSyncStatus, 'success');
    });

    test('round-trip with github method', () {
      final original = const SyncSettings(
        method: 'github',
        githubToken: 'ghp_xxxx',
        githubOwner: 'my-org',
        githubRepo: 'my-repo',
        githubBranch: 'main',
        githubPath: 'backup/sync.json',
        autoSyncEnabled: false,
        syncFullPracticeText: true,
      );
      final restored = SyncSettings.fromJson(original.toJson());
      expect(restored.method, 'github');
      expect(restored.githubToken, 'ghp_xxxx');
      expect(restored.githubOwner, 'my-org');
      expect(restored.githubRepo, 'my-repo');
      expect(restored.githubBranch, 'main');
      expect(restored.githubPath, 'backup/sync.json');
      expect(restored.autoSyncEnabled, false);
      expect(restored.syncFullPracticeText, true);
    });

    test('round-trip with gitee method', () {
      final original = const SyncSettings(
        method: 'gitee',
        giteeToken: 'gitee_token',
        giteeOwner: 'my-user',
        giteeRepo: 'my-repo',
        giteeBranch: 'master',
        giteePath: 'data/sync.json',
        syncPrivatePrepData: false,
        syncAiConfigMetadata: false,
      );
      final restored = SyncSettings.fromJson(original.toJson());
      expect(restored.method, 'gitee');
      expect(restored.giteeToken, 'gitee_token');
      expect(restored.giteeOwner, 'my-user');
      expect(restored.giteeRepo, 'my-repo');
      expect(restored.giteeBranch, 'master');
      expect(restored.giteePath, 'data/sync.json');
      expect(restored.syncPrivatePrepData, false);
      expect(restored.syncAiConfigMetadata, false);
    });

    test('round-trip with lastSyncAt set', () {
      final original = SyncSettings(
        method: 'local',
        lastSyncAt: now,
        lastSyncStatus: 'synced',
      );
      final restored = SyncSettings.fromJson(original.toJson());
      expect(restored.lastSyncAt, now);
      expect(restored.lastSyncStatus, 'synced');
    });

    test('fromJson old cloud method is normalized to local', () {
      final json = {
        'method': 'cloud',
        'autoSyncEnabled': true,
        'autoSyncIntervalMinutes': 5,
      };
      final restored = SyncSettings.fromJson(json);
      expect(restored.method, 'local');
    });

    test('fromJson missing fields use defaults', () {
      final json = <String, dynamic>{};
      final restored = SyncSettings.fromJson(json);
      expect(restored.method, 'local');
      expect(restored.webDavUrl, '');
      expect(restored.githubBranch, 'main');
      expect(restored.giteeBranch, 'master');
      expect(restored.githubPath, 'mianshi-zhilian/sync-state.json');
      expect(restored.giteePath, 'mianshi-zhilian/sync-state.json');
      expect(restored.autoSyncEnabled, true);
      expect(restored.autoSyncIntervalMinutes, 5);
      expect(restored.syncPrivatePrepData, true);
      expect(restored.lastSyncAt, isNull);
      expect(restored.lastSyncStatus, 'local_mode');
      expect(restored.syncAiConfigMetadata, false);
    });

    test('isAutomaticMethod returns true for webdav, github, gitee', () {
      expect(const SyncSettings(method: 'webdav').isAutomaticMethod, true);
      expect(const SyncSettings(method: 'github').isAutomaticMethod, true);
      expect(const SyncSettings(method: 'gitee').isAutomaticMethod, true);
      expect(const SyncSettings(method: 'local').isAutomaticMethod, false);
    });

    test('copyWith creates modified copy', () {
      final original = const SyncSettings(method: 'local');
      final modified = original.copyWith(
        method: 'github',
        githubToken: 'ghp_new',
        githubOwner: 'new-owner',
        autoSyncEnabled: false,
        lastSyncStatus: 'error',
      );
      expect(modified.method, 'github');
      expect(modified.githubToken, 'ghp_new');
      expect(modified.githubOwner, 'new-owner');
      expect(modified.autoSyncEnabled, false);
      expect(modified.lastSyncStatus, 'error');
      // Unchanged fields preserved
      expect(modified.webDavUrl, '');
      expect(modified.githubRepo, '');
      expect(modified.githubBranch, 'main');
      expect(modified.autoSyncIntervalMinutes, 5);
    });

    test('copyWith with null keeps original values', () {
      final original = const SyncSettings(
        method: 'github',
        githubToken: 'keep-me',
      );
      final modified = original.copyWith(method: 'webdav');
      expect(modified.method, 'webdav');
      expect(modified.githubToken, 'keep-me');
    });
  });

  group('PrepPlan', () {
    test('toJson/fromJson round-trip with all fields', () {
      final now = DateTime.now();
      final plan = PrepPlan(
        targetRole: 'Java后端',
        techStack: 'Spring,Redis',
        interviewDate: now.add(const Duration(days: 30)),
        dailyMinutes: 60,
        jobDescription: '精通Java、Spring Cloud',
        company: '字节跳动',
        currentLevel: 'intermediate',
        updatedAt: now,
      );
      final json = plan.toJson();
      final restored = PrepPlan.fromJson(json);
      expect(restored.targetRole, plan.targetRole);
      expect(restored.company, '字节跳动');
      expect(restored.currentLevel, 'intermediate');
      expect(restored.hasTarget, isTrue);
    });

    test('hasTarget works with company alone', () {
      final plan = PrepPlan(company: '阿里', updatedAt: DateTime.now());
      expect(plan.hasTarget, isTrue);
    });

    test('empty plan has no target', () {
      final plan = PrepPlan.empty();
      expect(plan.hasTarget, isFalse);
    });

    test('company and currentLevel are nullable', () {
      final plan = PrepPlan(updatedAt: DateTime.now());
      expect(plan.company, isNull);
      expect(plan.currentLevel, isNull);
    });

    test('toJson omits null company and currentLevel', () {
      final plan = PrepPlan(updatedAt: DateTime.now());
      final json = plan.toJson();
      expect(json.containsKey('company'), isFalse);
      expect(json.containsKey('currentLevel'), isFalse);
    });
  });
}
