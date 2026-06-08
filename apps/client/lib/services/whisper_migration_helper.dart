import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';
import '../models/ai_config.dart';
import 'storage_service.dart';

class WhisperMigrationHelper {
  static Future<void> migrateIfNeeded(StorageService storage, {String source = 'unknown'}) async {
    try {
      final rawData = await storage.load('settings');
      if (rawData is! Map<String, dynamic>) return;
      final oldBaseUrl = rawData['whisperBaseUrl'] as String?;
      final oldApiKey = rawData['whisperApiKey'] as String?;
      final oldModel = rawData['whisperModel'] as String?;
      if (oldBaseUrl == null || oldBaseUrl.trim().isEmpty) return;

      final existingConfigs = await storage.loadAiConfigs();
      final alreadyMigrated = existingConfigs.any(
        (c) =>
            c.baseUrl == oldBaseUrl &&
            c.audioMode == AiAudioMode.transcriptionEndpoint,
      );
      if (alreadyMigrated) return;

      final migratedConfig = AiConfig(
        id: 'whisper_migrated_${DateTime.now().millisecondsSinceEpoch}',
        name: oldModel != null && oldModel.isNotEmpty
            ? 'Whisper ($oldModel)'
            : L10n.get('whisper_default_name', L10n.currentLanguage),
        baseUrl: oldBaseUrl,
        apiKey: oldApiKey ?? '',
        model: oldModel ?? 'whisper-1',
        isDefault: existingConfigs.isEmpty,
        enabled: true,
        supportsTextInput: false,
        supportsImageInput: false,
        supportsAudioInput: true,
        supportsMultimodal: false,
        supportsStreaming: true,
        audioMode: AiAudioMode.transcriptionEndpoint,
        usageTags: const ['stt'],
        capabilityTests: {
          AiCapability.audio.key: CapabilityTestRecord(
            state: CapabilityTestState.untested,
            testedAt: DateTime.now(),
            message: 'migrated_from_old_settings',
          ),
        },
      );
      await storage.saveAiConfigs([...existingConfigs, migratedConfig]);
      debugPrint('WhisperMigrationHelper[$source]: migrated old whisper config to AiConfig');
    } catch (e) {
      debugPrint('WhisperMigrationHelper[$source]: migration failed: $e');
    }
  }
}
