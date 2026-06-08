import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/services/whisper_migration_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.currentLanguage = L10n.defaultLanguage;
  });

  Future<StorageService> _setupStorageWithSettings({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    final storage = StorageService();
    await storage.save('settings', {
      if (baseUrl != null) 'whisperBaseUrl': baseUrl,
      if (apiKey != null) 'whisperApiKey': apiKey,
      if (model != null) 'whisperModel': model,
    });
    return storage;
  }

  Future<AiConfig?> _getMigratedConfig(StorageService storage) async {
    final configs = await storage.loadAiConfigs();
    return configs.isNotEmpty ? configs.first : null;
  }

  group('WhisperMigrationHelper.migrateIfNeeded', () {
    test('1. creates AiConfig with correct fields when all whisper fields present', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final config = await _getMigratedConfig(storage);
      expect(config, isNotNull);
      expect(config!.baseUrl, 'https://api.openai.com');
      expect(config.apiKey, 'sk-test-key');
      expect(config.model, 'whisper-1');
      expect(config.id, startsWith('whisper_migrated_'));
      expect(config.name, 'Whisper (whisper-1)');
      expect(config.providerType, 'openai_compatible');
      expect(config.supportsAudioInput, isTrue);
      expect(config.supportsTextInput, isFalse);
      expect(config.supportsImageInput, isFalse);
      expect(config.supportsMultimodal, isFalse);
      expect(config.enabled, isTrue);
      expect(config.isDefault, isTrue);
    });

    test('2. does nothing when settings is null', () async {
      final storage = StorageService();

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final configs = await storage.loadAiConfigs();
      expect(configs, isEmpty);
    });

    test('3. does nothing when whisperBaseUrl is empty', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: '',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final configs = await storage.loadAiConfigs();
      expect(configs, isEmpty);
    });

    test('4. does nothing when already migrated (matching baseUrl + transcriptionEndpoint)', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);
      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final configs = await storage.loadAiConfigs();
      expect(configs, hasLength(1));
    });

    test('5. sets supportsStreaming: true and audioMode: transcriptionEndpoint', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final config = await _getMigratedConfig(storage);
      expect(config!.supportsStreaming, isTrue);
      expect(config.audioMode, AiAudioMode.transcriptionEndpoint);
    });

    test('6. uses whisper-1 as default model when oldModel is null', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final config = await _getMigratedConfig(storage);
      expect(config!.model, 'whisper-1');
      expect(
        config.name,
        L10n.get('whisper_default_name', L10n.currentLanguage),
      );
    });

    test('7. sets usageTags to [stt]', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      await WhisperMigrationHelper.migrateIfNeeded(storage);

      final config = await _getMigratedConfig(storage);
      expect(config!.usageTags, ['stt']);
    });

    test('8. includes source name in debugPrint output', () async {
      final storage = await _setupStorageWithSettings(
        baseUrl: 'https://api.openai.com',
        apiKey: 'sk-test-key',
        model: 'whisper-1',
      );

      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
      });

      await WhisperMigrationHelper.migrateIfNeeded(storage, source: 'test_source');

      expect(logs.any((l) => l.contains('test_source')), isTrue);
    });
  });
}
