import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _contentCacheKey(String baseUrl, String key) =>
    'content_cache_${baseUrl.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}_$key';

void main() {
  group('sync package privacy', () {
    test(
      'default export redacts practice answers and skips answer versions',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.saveSessions([
          PracticeSession(
            id: 'session-1',
            topicId: 'topic-1',
            startedAt: DateTime(2026, 1, 2, 9),
            completedAt: DateTime(2026, 1, 2, 10),
            score: 80,
            feedback: 'private feedback quotes my answer',
          ),
        ]);
        await storage.savePracticeAttempts([
          PracticeAttempt(
            id: 'attempt-1',
            topicId: 'topic-1',
            mode: 'recall',
            question: 'Question',
            answer: 'private answer',
            createdAt: DateTime(2026, 1, 2),
            improvedAnswer: 'private improved answer',
          ),
        ]);
        await storage.saveJsonList('answer_versions_topic-1', [
          {
            'type': 'draft',
            'content': 'private answer version',
            'createdAt': '2026-01-02 10:00',
          },
        ]);

        final package = await storage.exportSyncPackage(const SyncSettings());
        final data = package['data'] as Map<String, dynamic>;
        final attempts = data['practice_attempts'] as List<dynamic>;
        final sessions = data['sessions'] as List<dynamic>;

        expect(attempts.single['answer'], isEmpty);
        expect(attempts.single['improvedAnswer'], isNull);
        expect(sessions.single['feedback'], isNull);
        expect(data.containsKey('answer_versions'), isFalse);
      },
    );

    test('export includes content environment and version metadata', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      const settings = AppSettings(contentEnv: ContentEnv.staging);
      await storage.saveSettings(settings);
      await storage.save(
        _contentCacheKey(settings.contentBaseUrl, 'content_version'),
        'content-2026-06-05',
      );

      final package = await storage.exportSyncPackage(const SyncSettings());

      expect(package['contentEnv'], 'staging');
      expect(package['contentVersion'], 'content-2026-06-05');
    });

    test('default export skips AI config metadata', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.saveAiConfigs([
        const AiConfig(
          id: 'ai-1',
          name: 'Private Gateway',
          baseUrl: 'https://ai.internal.example.com',
          apiKey: 'sk-secret',
          model: 'gpt-4o',
        ),
      ]);

      final package = await storage.exportSyncPackage(const SyncSettings());
      final data = package['data'] as Map<String, dynamic>;

      expect(data.containsKey('ai_configs'), isFalse);
    });

    test('opt-in export syncs AI metadata without apiKey', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.saveAiConfigs([
        const AiConfig(
          id: 'ai-1',
          name: 'Private Gateway',
          baseUrl: 'https://ai.internal.example.com',
          apiKey: 'sk-secret',
          model: 'gpt-4o',
        ),
      ]);

      final package = await storage.exportSyncPackage(
        const SyncSettings(syncAiConfigMetadata: true),
      );
      final data = package['data'] as Map<String, dynamic>;
      final configs = data['ai_configs'] as List<dynamic>;

      expect(configs.single['name'], 'Private Gateway');
      expect(configs.single['apiKey'], isEmpty);
    });

    test('default import ignores remote AI config metadata', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.saveAiConfigs([
        const AiConfig(
          id: 'local-ai',
          name: 'Local AI',
          baseUrl: 'https://local.example.com',
          apiKey: 'local-secret',
          model: 'local-model',
        ),
      ]);

      await storage.importSyncPackage({
        'schemaVersion': 1,
        'app': 'mianshi-zhilian',
        'data': {
          'ai_configs': [
            {
              'id': 'remote-ai',
              'name': 'Remote AI',
              'baseUrl': 'https://remote.example.com',
              'apiKey': '',
              'model': 'remote-model',
            },
          ],
        },
      }, syncSettings: const SyncSettings());

      final configs = await storage.loadAiConfigs();
      expect(configs.map((c) => c.id), ['local-ai']);
    });

    test(
      'full-answer export includes practice answers and answer versions',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.saveSessions([
          PracticeSession(
            id: 'session-1',
            topicId: 'topic-1',
            startedAt: DateTime(2026, 1, 2, 9),
            completedAt: DateTime(2026, 1, 2, 10),
            score: 80,
            feedback: 'private feedback quotes my answer',
          ),
        ]);
        await storage.savePracticeAttempts([
          PracticeAttempt(
            id: 'attempt-1',
            topicId: 'topic-1',
            mode: 'recall',
            question: 'Question',
            answer: 'private answer',
            createdAt: DateTime(2026, 1, 2),
            improvedAnswer: 'private improved answer',
          ),
        ]);
        await storage.saveJsonList('answer_versions_topic-1', [
          {
            'type': 'draft',
            'content': 'private answer version',
            'createdAt': '2026-01-02 10:00',
          },
        ]);

        final package = await storage.exportSyncPackage(
          const SyncSettings(syncFullPracticeText: true),
        );
        final data = package['data'] as Map<String, dynamic>;
        final attempts = data['practice_attempts'] as List<dynamic>;
        final sessions = data['sessions'] as List<dynamic>;
        final answerVersions = data['answer_versions'] as Map<String, dynamic>;

        expect(attempts.single['answer'], 'private answer');
        expect(attempts.single['improvedAnswer'], 'private improved answer');
        expect(
          sessions.single['feedback'],
          'private feedback quotes my answer',
        );
        expect(
          answerVersions['topic-1'].single['content'],
          'private answer version',
        );
      },
    );

    test(
      'sanitized import preserves existing local sensitive fields',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.saveSessions([
          PracticeSession(
            id: 'session-1',
            topicId: 'topic-1',
            startedAt: DateTime(2026, 1, 2, 9),
            completedAt: DateTime(2026, 1, 2, 10),
            score: 70,
            feedback: 'local private feedback',
          ),
        ]);
        await storage.savePracticeAttempts([
          PracticeAttempt(
            id: 'attempt-1',
            topicId: 'topic-1',
            mode: 'recall',
            question: 'Question',
            answer: 'local private answer',
            createdAt: DateTime(2026, 1, 2),
            improvedAnswer: 'local private improved answer',
          ),
        ]);

        await storage.importSyncPackage(
          {
            'schemaVersion': 1,
            'app': 'mianshi-zhilian',
            'data': {
              'sessions': [
                {
                  'id': 'session-1',
                  'topicId': 'topic-1',
                  'startedAt': DateTime(2026, 1, 2, 9).toIso8601String(),
                  'completedAt': DateTime(2026, 1, 2, 10).toIso8601String(),
                  'score': 90,
                  'feedback': null,
                },
              ],
              'practice_attempts': [
                {
                  'id': 'attempt-1',
                  'topicId': 'topic-1',
                  'promptId': '',
                  'mode': 'recall',
                  'question': 'Question',
                  'answer': '',
                  'createdAt': DateTime(2026, 1, 2).toIso8601String(),
                  'score': 88,
                  'improvedAnswer': null,
                  'missedPoints': <String>[],
                  'wrongPoints': <String>[],
                  'errorTags': <String>[],
                  'aiEvaluated': true,
                  'localOnly': false,
                  'analysisStatus': 'success',
                },
              ],
            },
          },
          syncSettings: const SyncSettings(),
          preserveLocalSensitiveData: true,
        );

        final attempts = await storage.loadPracticeAttempts();
        expect(attempts.single.answer, 'local private answer');
        expect(attempts.single.improvedAnswer, 'local private improved answer');
        expect(attempts.single.score, 88);
        final sessions = await storage.loadSessions();
        expect(sessions.single.feedback, 'local private feedback');
        expect(sessions.single.score, 90);
      },
    );
  });
}
