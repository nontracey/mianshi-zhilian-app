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
}
