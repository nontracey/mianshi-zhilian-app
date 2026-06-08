import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';

void main() {
  group('save / load round-trip', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('String', () async {
      final storage = StorageService();
      await storage.save('test_key', 'hello world');
      final result = await storage.load('test_key');
      expect(result, 'hello world');
    });

    test('Map', () async {
      final storage = StorageService();
      await storage.save('map_key', {'a': 1, 'b': 'two'});
      final result = await storage.load('map_key');
      expect(result, {'a': 1, 'b': 'two'});
    });

    test('List', () async {
      final storage = StorageService();
      await storage.save('list_key', [1, 'two', 3.0]);
      final result = await storage.load('list_key');
      expect(result, [1, 'two', 3.0]);
    });

    test('int', () async {
      final storage = StorageService();
      await storage.save('int_key', 42);
      final result = await storage.load('int_key');
      expect(result, 42);
    });

    test('null for missing key', () async {
      final storage = StorageService();
      final result = await storage.load('nonexistent');
      expect(result, isNull);
    });
  });

  group('AppSettings persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      final storage = StorageService();
      const settings = AppSettings(
        language: 'en',
        currentDomain: 'flutter',
        dailyNewCount: 5,
        fontScale: 1.2,
      );
      await storage.saveSettings(settings);
      final loaded = await storage.loadSettings();
      expect(loaded.language, 'en');
      expect(loaded.currentDomain, 'flutter');
      expect(loaded.dailyNewCount, 5);
      expect(loaded.fontScale, 1.2);
    });

    test('returns default AppSettings when nothing saved', () async {
      final storage = StorageService();
      final loaded = await storage.loadSettings();
      expect(loaded.language, 'zh');
      expect(loaded.themeType, AppThemeType.system);
    });
  });

  group('AiConfig persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      final storage = StorageService();
      final configs = [
        AiConfig(
          id: 'cfg-1',
          name: 'GPT-4o',
          baseUrl: 'https://api.openai.com',
          apiKey: 'sk-test',
          model: 'gpt-4o',
          isDefault: true,
        ),
        AiConfig(
          id: 'cfg-2',
          name: 'Claude',
          baseUrl: 'https://api.anthropic.com',
          apiKey: 'sk-ant-test',
          model: 'claude-3',
        ),
      ];
      await storage.saveAiConfigs(configs);
      final loaded = await storage.loadAiConfigs();
      expect(loaded.length, 2);
      expect(loaded[0].id, 'cfg-1');
      expect(loaded[0].name, 'GPT-4o');
      expect(loaded[0].apiKey, 'sk-test');
      expect(loaded[0].isDefault, true);
      expect(loaded[1].id, 'cfg-2');
      expect(loaded[1].baseUrl, 'https://api.anthropic.com');
    });

    test('returns empty list when nothing saved', () async {
      final storage = StorageService();
      final loaded = await storage.loadAiConfigs();
      expect(loaded, isEmpty);
    });
  });

  group('device ID', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates and persists a UUID', () async {
      final storage = StorageService();
      final id = await storage.getOrCreateDeviceId();
      expect(id, isA<String>());
      expect(id.isNotEmpty, isTrue);
      expect(Uri.tryParse(id), isNotNull);
    });

    test('returns same ID on subsequent calls', () async {
      final storage = StorageService();
      final first = await storage.getOrCreateDeviceId();
      final second = await storage.getOrCreateDeviceId();
      expect(second, first);
    });
  });

  group('analytics buffer lifecycle', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('records feature, snapshots, and removes on flush', () async {
      final storage = StorageService();

      await storage.recordAnalyticsFeature('login');
      await storage.recordAnalyticsFeature('sync_success');

      final snapshot = await storage.snapshotAnalyticsBufferForFlush();
      expect(snapshot, isNotNull);
      final batchId = snapshot!['batch_id'] as String;
      expect(batchId, isA<String>());

      final days = snapshot['days'] as Map<String, dynamic>;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final day = days[today] as Map<String, dynamic>;
      final features = day['feature_counts'] as Map<String, dynamic>;
      expect(features['login'], 1);
      expect(features['sync_success'], 1);

      await storage.markAnalyticsFlushSuccess(batchId, days);

      final buffer = await storage.loadAnalyticsBuffer();
      final remainingDays = buffer['days'] as Map<String, dynamic>;
      expect(remainingDays[today], isNull);
    });
  });

  group('sync dirty flag', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts clean', () async {
      final storage = StorageService();
      expect(await storage.hasSyncDirty(), isFalse);
    });

    test('marks dirty then clear', () async {
      final storage = StorageService();
      await storage.markSyncDirty();
      expect(await storage.hasSyncDirty(), isTrue);

      await storage.clearSyncDirty();
      expect(await storage.hasSyncDirty(), isFalse);
    });
  });

  group('disabled domains', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns empty list when nothing saved', () async {
      final storage = StorageService();
      final domains = await storage.loadDisabledDomains();
      expect(domains, isEmpty);
    });

    test('save and load round-trip', () async {
      final storage = StorageService();
      await storage.saveDisabledDomains(['java', 'flutter', 'system_design']);
      final loaded = await storage.loadDisabledDomains();
      expect(loaded, ['java', 'flutter', 'system_design']);
    });

    test('overwrites previous list', () async {
      final storage = StorageService();
      await storage.saveDisabledDomains(['java']);
      await storage.saveDisabledDomains(['flutter']);
      final loaded = await storage.loadDisabledDomains();
      expect(loaded, ['flutter']);
    });
  });
}
