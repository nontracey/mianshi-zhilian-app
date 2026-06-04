import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/ai_config.dart';
import '../models/topic.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';

class AiProvider extends ChangeNotifier {
  final AiService _aiService;
  final StorageService _storage;

  AiProvider(this._aiService, this._storage);

  List<AiConfig> _configs = [];
  AiConfig? _defaultConfig;
  bool _isTesting = false;
  String? _testResult;

  // 流式评估的订阅及相关资源，用于取消和清理
  StreamSubscription<String>? _currentStreamSubscription;
  StreamController<String>? _currentStreamController;
  Completer<Map<String, dynamic>>? _currentCompleter;

  List<AiConfig> get configs => _configs;
  AiConfig? get defaultConfig => _defaultConfig;
  List<AiConfig> get enabledConfigs =>
      _configs.where((c) => c.enabled).toList(growable: false);
  bool get isTesting => _isTesting;
  String? get testResult => _testResult;
  bool get hasAnyConfig => _configs.any((c) => c.enabled);
  bool get hasUsableDefaultConfig => _defaultConfig?.canEvaluate == true;

  @override
  void dispose() {
    _cancelCurrentStream();
    super.dispose();
  }

  Future<void> loadConfigs() async {
    await _migrateOldWhisperConfigIfNeeded();
    _configs = await _storage.loadAiConfigs();
    _defaultConfig = _configs.where((c) => c.isDefault).firstOrNull;
    notifyListeners();
  }

  Future<void> _migrateOldWhisperConfigIfNeeded() async {
    try {
      final rawData = await _storage.load('settings');
      if (rawData is! Map<String, dynamic>) return;
      final oldBaseUrl = rawData['whisperBaseUrl'] as String?;
      final oldApiKey = rawData['whisperApiKey'] as String?;
      final oldModel = rawData['whisperModel'] as String?;
      if (oldBaseUrl == null || oldBaseUrl.trim().isEmpty) return;

      final existingConfigs = await _storage.loadAiConfigs();
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
            : L10n.get('whisper_default_name', 'zh'),
        baseUrl: oldBaseUrl,
        apiKey: oldApiKey ?? '',
        model: oldModel ?? 'whisper-1',
        isDefault: existingConfigs.isEmpty,
        enabled: true,
        supportsTextInput: false,
        supportsImageInput: false,
        supportsAudioInput: true,
        supportsMultimodal: false,
        supportsStreaming: false,
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
      await _storage.saveAiConfigs([...existingConfigs, migratedConfig]);
    } catch (e) {
      debugPrint('AiProvider: whisper migration failed: $e');
    }
  }

  Future<void> addConfig(AiConfig config) async {
    _configs.add(config);
    if (config.isDefault) {
      _configs = _configs
          .map((c) => c.id == config.id ? c : c.copyWith(isDefault: false))
          .toList();
      _defaultConfig = config;
    }
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  Future<void> updateConfig(AiConfig config) async {
    final index = _configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      if (config.isDefault) {
        _configs = _configs
            .map(
              (c) => c.id == config.id ? config : c.copyWith(isDefault: false),
            )
            .toList();
        _defaultConfig = config;
      } else {
        _configs[index] = config;
        if (_defaultConfig?.id == config.id) {
          _defaultConfig = config;
        }
      }
      await _storage.saveAiConfigs(_configs);
      notifyListeners();
    }
  }

  Future<void> deleteConfig(String id) async {
    _configs.removeWhere((c) => c.id == id);
    if (_defaultConfig?.id == id) {
      _defaultConfig = _configs.where((c) => c.isDefault).firstOrNull;
    }
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  Future<void> setDefault(String id) async {
    _configs = _configs.map((c) {
      if (c.id == id) {
        _defaultConfig = c.copyWith(isDefault: true);
        return _defaultConfig!;
      }
      return c.copyWith(isDefault: false);
    }).toList();
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  /// Alias for setDefault
  Future<void> setDefaultConfig(String id) async => setDefault(id);

  Future<void> testConnection(String id) async {
    final config = _configs.where((c) => c.id == id).firstOrNull;
    if (config == null) return;

    _isTesting = true;
    _testResult = null;
    notifyListeners();

    try {
      final result = await testCapability(id, AiCapability.text);
      _testResult = L10n.get(result.messageKey, 'zh');
    } catch (e) {
      _testResult = L10n.getp('connection_failed_with_error', 'zh', {
        'error': '$e',
      });
    }

    _isTesting = false;
    notifyListeners();
  }

  Future<AiTestResult> testCapability(
    String id,
    AiCapability capability,
  ) async {
    final config = _configs.where((c) => c.id == id).firstOrNull;
    if (config == null) {
      return const AiTestResult(
        success: false,
        messageKey: 'ai_config_not_found',
      );
    }
    final result = switch (capability) {
      AiCapability.text => await _aiService.testTextConnection(config),
      AiCapability.audio => await _aiService.testAudioConnection(config),
      AiCapability.image => const AiTestResult(
        success: false,
        messageKey: 'image_test_not_ready',
      ),
    };
    final updatedTests = Map<String, CapabilityTestRecord>.from(
      config.capabilityTests,
    );
    updatedTests[capability.key] = CapabilityTestRecord(
      state: result.success
          ? CapabilityTestState.passed
          : CapabilityTestState.failed,
      testedAt: DateTime.now(),
      message: result.detail.isNotEmpty ? result.detail : result.messageKey,
    );
    await updateConfig(config.copyWith(capabilityTests: updatedTests));
    return result;
  }

  /// Test connection with explicit baseUrl/apiKey/model
  Future<AiTestResult> testConnectionWithParams({
    required String baseUrl,
    required String apiKey,
    required String model,
    AiAudioMode audioMode = AiAudioMode.none,
    AiCapability capability = AiCapability.text,
  }) async {
    final tempConfig = AiConfig(
      id: '_test',
      name: '_test',
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      audioMode: audioMode,
    );
    return switch (capability) {
      AiCapability.text => _aiService.testTextConnection(tempConfig),
      AiCapability.audio => _aiService.testAudioConnection(tempConfig),
      AiCapability.image => Future.value(
        const AiTestResult(success: false, messageKey: 'image_test_not_ready'),
      ),
    };
  }

  AiConfig? configById(String? id) {
    if (id == null || id.isEmpty) return _defaultConfig;
    return _configs.where((c) => c.id == id).firstOrNull;
  }

  AiConfig? _selectConfig(String? id, String usageTag) {
    if (id != null && id.isNotEmpty) return configById(id);

    final matchingDefault =
        _defaultConfig != null && _defaultConfig!.usageTags.contains(usageTag)
        ? _defaultConfig
        : null;
    return matchingDefault ??
        enabledConfigs
            .where((config) => config.usageTags.contains(usageTag))
            .cast<AiConfig?>()
            .firstOrNull ??
        _defaultConfig ??
        enabledConfigs.cast<AiConfig?>().firstOrNull;
  }

  /// Evaluate a user's answer using a user-provided AI config.
  Future<Map<String, dynamic>> evaluateAnswer({
    String? aiConfigId,
    String usageTag = 'recall',
    required String topicId,
    required String question,
    required String userAnswer,
    Rubric? rubric,
    Uint8List? imageBytes,
  }) async {
    final config = _selectConfig(aiConfigId, usageTag);
    if (config == null || !config.canEvaluate) {
      return {
        'score': null,
        'level': 'local',
        'summary': L10n.get('ai_not_configured_summary', 'zh'),
        'missedPoints': <String>[],
        'wrongPoints': <String>[],
        'errorPoints': <String>[],
        'improvedAnswer': '',
        'nextAction': L10n.get('ai_not_configured_action', 'zh'),
        'aiUnavailable': true,
      };
    }
    return _aiService.evaluateAnswer(
      config: config,
      topicTitle: question,
      mustHave: rubric?.mustHave ?? [],
      commonMistakes: rubric?.commonMistakes ?? [],
      userAnswer: userAnswer,
      language: 'zh',
      imageBytes: imageBytes,
    );
  }

  /// Evaluate a user's answer with streaming support
  /// Returns a stream of content chunks, and a future with the final parsed result
  ({Stream<String> stream, Future<Map<String, dynamic>> result})
  evaluateAnswerStream({
    String? aiConfigId,
    String usageTag = 'recall',
    required String topicId,
    required String question,
    required String userAnswer,
    Rubric? rubric,
    Uint8List? imageBytes,
  }) {
    final config = _selectConfig(aiConfigId, usageTag);
    if (config == null || !config.canEvaluate) {
      final result = Future.value({
        'score': null,
        'level': 'local',
        'summary': L10n.get('ai_not_configured_summary', 'zh'),
        'missedPoints': <String>[],
        'wrongPoints': <String>[],
        'errorPoints': <String>[],
        'improvedAnswer': '',
        'nextAction': L10n.get('ai_not_configured_action', 'zh'),
        'aiUnavailable': true,
      });
      return (stream: const Stream.empty(), result: result);
    }

    // 取消之前的流并清理旧 StreamController/Completer
    _cancelCurrentStream();

    final streamController = StreamController<String>();
    final completer = Completer<Map<String, dynamic>>();
    _currentStreamController = streamController;
    _currentCompleter = completer;

    String fullContent = '';

    _currentStreamSubscription = _aiService
        .evaluateAnswerStream(
          config: config,
          topicTitle: question,
          mustHave: rubric?.mustHave ?? [],
          commonMistakes: rubric?.commonMistakes ?? [],
          userAnswer: userAnswer,
          language: 'zh',
          imageBytes: imageBytes,
        )
        .listen(
          (chunk) {
            fullContent += chunk;
            streamController.add(chunk);
          },
          onDone: () {
            if (!streamController.isClosed) streamController.close();
            if (_currentStreamController == streamController) {
              _currentStreamSubscription = null;
              _currentStreamController = null;
              _currentCompleter = null;
            }
            // 解析完整内容
            final result = _parseStreamResult(fullContent);
            if (!completer.isCompleted) completer.complete(result);
          },
          onError: (error) {
            if (!streamController.isClosed) streamController.close();
            if (_currentStreamController == streamController) {
              _currentStreamSubscription = null;
              _currentStreamController = null;
              _currentCompleter = null;
            }
            if (!completer.isCompleted) completer.completeError(error);
          },
          cancelOnError: true,
        );

    return (stream: streamController.stream, result: completer.future);
  }

  /// 取消当前流式评估
  void cancelStreamEvaluation() {
    _cancelCurrentStream();
  }

  /// 取消当前流式评估并清理资源（StreamController/Completer）
  void _cancelCurrentStream() {
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
    // 关闭旧 StreamController 使其监听者收到 done 事件
    if (_currentStreamController != null &&
        !_currentStreamController!.isClosed) {
      _currentStreamController!.close();
    }
    _currentStreamController = null;
    // 完成旧 Completer 避免永久挂起
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete({
        'score': null,
        'level': 'local',
        'summary': 'cancelled',
        'missedPoints': <String>[],
        'wrongPoints': <String>[],
        'improvedAnswer': '',
        'nextAction': '',
        'aiUnavailable': true,
      });
    }
    _currentCompleter = null;
  }

  Future<String> transcribeAudio({
    required AiConfig config,
    required Uint8List audioBytes,
    String language = 'zh',
  }) {
    return _aiService.transcribeAudio(
      config: config,
      audioBytes: audioBytes,
      language: language,
    );
  }

  Map<String, dynamic> _parseStreamResult(String content) {
    // 尝试从回复中提取 JSON
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      try {
        return _normalizeEvaluationResult(
          json.decode(jsonMatch.group(0)!) as Map<String, dynamic>,
        );
      } catch (_) {
        // JSON 解析失败
      }
    }
    // JSON 解析失败或没有可解析内容时，返回 aiUnavailable 标记
    // 上层据此跳过掌握度更新，避免因格式异常而清零用户掌握度
    return {
      'score': null,
      'level': 'local',
      'summary': content.isNotEmpty
          ? content
          : L10n.get('evaluation_parse_failed', 'zh'),
      'missedPoints': <String>[],
      'wrongPoints': <String>[],
      'improvedAnswer': '',
      'nextAction': L10n.get('retry', 'zh'),
      'aiUnavailable': true,
    };
  }

  Map<String, dynamic> _normalizeEvaluationResult(Map<String, dynamic> raw) {
    final result = Map<String, dynamic>.from(raw);
    final score = _parseScore(result['score']);
    result['score'] = score;
    result['level'] = (result['level'] as String?) ?? _levelForScore(score);
    result['summary'] = result['summary']?.toString() ?? '';
    result['missedPoints'] = _stringList(result['missedPoints']);
    result['wrongPoints'] = _stringList(
      result['wrongPoints'] ?? result['errorPoints'],
    );
    result['improvedAnswer'] =
        (result['improvedAnswer'] ?? result['optimizedAnswer'])?.toString() ??
        '';
    result['nextAction'] = result['nextAction']?.toString() ?? '';
    if (score == null) result['aiUnavailable'] = true;
    return result;
  }

  int? _parseScore(Object? value) {
    final number = switch (value) {
      int v => v,
      double v => v.round(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };
    if (number == null) return null;
    return number.clamp(0, 100);
  }

  String _levelForScore(int? score) {
    if (score == null) return 'local';
    if (score >= 85) return 'skilled';
    if (score >= 60) return 'familiar';
    return 'unfamiliar';
  }

  List<String> _stringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value == null) return <String>[];
    final text = value.toString().trim();
    return text.isEmpty ? <String>[] : <String>[text];
  }

  /// 通用流式聊天，用于 AI 改进等场景
  Stream<String> sendMessageStream(String userMessage, {String? systemPrompt}) {
    final config =
        _defaultConfig ??
        _configs.firstWhere(
          (c) => c.enabled,
          orElse: () =>
              throw Exception(L10n.get('no_ai_config_available', 'zh')),
        );
    return _aiService.sendMessageStream(
      config: config,
      userMessage: userMessage,
      systemPrompt: systemPrompt,
    );
  }
}
