import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('analytics buffer', () {
    test('keeps the same batch id until a flush succeeds', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();

      await storage.incrementAnalyticsCounter('open_count');
      final firstSnapshot = await storage.snapshotAnalyticsBufferForFlush();
      final secondSnapshot = await storage.snapshotAnalyticsBufferForFlush();

      expect(firstSnapshot, isNotNull);
      expect(secondSnapshot, isNotNull);
      expect(secondSnapshot!['batch_id'], firstSnapshot!['batch_id']);
    });

    test(
      'successful flush only removes sent counts from the same day',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        final today = DateTime.now().toIso8601String().substring(0, 10);

        await storage.incrementAnalyticsCounter('open_count');
        final sentSnapshot = await storage.snapshotAnalyticsBufferForFlush();
        await storage.incrementAnalyticsNestedCounter(
          'section_counts',
          'profile',
        );

        await storage.markAnalyticsFlushSuccess(
          sentSnapshot!['batch_id'] as String,
          sentSnapshot['days'] as Map<String, dynamic>,
        );

        final buffer = await storage.loadAnalyticsBuffer();
        final days = buffer['days'] as Map<String, dynamic>;
        final day = days[today] as Map<String, dynamic>;
        final sections = day['section_counts'] as Map<String, dynamic>;

        expect(day.containsKey('open_count'), isFalse);
        expect(sections['profile'], 1);
        expect(buffer['batch_id'], isNot(sentSnapshot['batch_id']));
      },
    );

    test('feature counters share the analytics batch buffer', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await storage.incrementAnalyticsCounter('open_count');
      await storage.recordAnalyticsFeature('login');

      final snapshot = await storage.snapshotAnalyticsBufferForFlush();
      final days = snapshot!['days'] as Map<String, dynamic>;
      final day = days[today] as Map<String, dynamic>;
      final features = day['feature_counts'] as Map<String, dynamic>;

      expect(day['open_count'], 1);
      expect(features['login'], 1);
      expect(snapshot['batch_id'], isA<String>());
    });
  });
}
