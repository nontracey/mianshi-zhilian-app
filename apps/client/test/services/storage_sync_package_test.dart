import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('sync package privacy', () {
    test(
      'default export redacts practice answers and skips answer versions',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
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

        expect(attempts.single['answer'], isEmpty);
        expect(attempts.single['improvedAnswer'], isNull);
        expect(data.containsKey('answer_versions'), isFalse);
      },
    );

    test(
      'full-answer export includes practice answers and answer versions',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
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
        final answerVersions = data['answer_versions'] as Map<String, dynamic>;

        expect(attempts.single['answer'], 'private answer');
        expect(attempts.single['improvedAnswer'], 'private improved answer');
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
      },
    );
  });
}
