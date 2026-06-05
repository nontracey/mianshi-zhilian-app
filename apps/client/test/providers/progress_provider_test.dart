import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'readiness remains zero before any scored progress or mock interview',
    () {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      final topics = [
        const Topic(
          id: 'topic-1',
          domain: 'java',
          category: 'concurrency',
          title: 'AQS',
          summary: 'AbstractQueuedSynchronizer',
        ),
      ];

      expect(provider.readinessScore(topics), 0);
    },
  );

  test('smart recommendations prioritize unmet prerequisites', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ProgressProvider(StorageService());
    final prerequisite = const Topic(
      id: 'java.core.base',
      domain: 'java',
      category: 'core',
      title: 'Base',
      summary: 'Base',
      order: 1,
      recommendWeight: 30,
    );
    final advanced = const Topic(
      id: 'java.core.advanced',
      domain: 'java',
      category: 'core',
      title: 'Advanced',
      summary: 'Advanced',
      order: 2,
      recommendWeight: 100,
      prerequisites: ['java.core.base'],
    );

    final before = provider.getRecommendedTopics('java', [
      advanced,
      prerequisite,
    ], 'smart');
    expect(before.first.id, prerequisite.id);

    await provider.updateTopicProgress(prerequisite.id, score: 70);

    final after = provider.getRecommendedTopics('java', [
      advanced,
      prerequisite,
    ], 'smart');
    expect(after.first.id, advanced.id);
  });
}
