import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  
  // 流式评估的订阅，用于取消
  StreamSubscription<String>? _currentStreamSubscription;

  List<AiConfig> get configs => _configs;
  AiConfig? get defaultConfig => _defaultConfig;
  List<AiConfig> get enabledConfigs =>
      _configs.where((c) => c.enabled).toList(growable: false);
  bool get isTesting => _isTesting;
  String? get testResult => _testResult;
  bool get hasAnyConfig => _configs.any((c) => c.enabled);

  @override
  void dispose() {
    _currentStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadConfigs() async {
    _configs = await _storage.loadAiConfigs();
    _defaultConfig = _configs.where((c) => c.isDefault).firstOrNull;
    notifyListeners();
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
      final success = await _aiService.testConnection(config);
      _testResult = success ? '连接成功' : '连接失败';
    } catch (e) {
      _testResult = '连接失败: $e';
    }

    _isTesting = false;
    notifyListeners();
  }

  /// Test connection with explicit baseUrl/apiKey/model
  Future<bool> testConnectionWithParams({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final tempConfig = AiConfig(
      id: '_test',
      name: '_test',
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
    return _aiService.testConnection(tempConfig);
  }

  AiConfig? configById(String? id) {
    if (id == null || id.isEmpty) return _defaultConfig;
    return _configs.where((c) => c.id == id).firstOrNull;
  }

  /// Evaluate a user's answer using a user-provided AI config.
  Future<Map<String, dynamic>> evaluateAnswer({
    String? aiConfigId,
    required String topicId,
    required String question,
    required String userAnswer,
    Rubric? rubric,
    Uint8List? imageBytes,
  }) async {
    final config = configById(aiConfigId);
    if (config == null || !config.enabled) {
      return {
        'score': null,
        'level': 'local',
        'summary': '还没有配置可用的 AI 模型。本次回答已按本地练习保存，配置 AI 后可以重新评估。',
        'missedPoints': <String>[],
        'wrongPoints': <String>[],
        'errorPoints': <String>[],
        'improvedAnswer': '',
        'nextAction': '前往个人中心配置 AI，或继续本地练习',
        'aiUnavailable': true,
      };
    }
    return _aiService.evaluateAnswer(
      config: config,
      topicTitle: question,
      mustHave: rubric?.mustHave ?? [],
      commonMistakes: rubric?.commonMistakes ?? [],
      userAnswer: userAnswer,
      language: '中文',
      imageBytes: imageBytes,
    );
  }

  /// Evaluate a user's answer with streaming support
  /// Returns a stream of content chunks, and a future with the final parsed result
  ({Stream<String> stream, Future<Map<String, dynamic>> result}) evaluateAnswerStream({
    String? aiConfigId,
    required String topicId,
    required String question,
    required String userAnswer,
    Rubric? rubric,
    Uint8List? imageBytes,
  }) {
    final config = configById(aiConfigId);
    if (config == null || !config.enabled) {
      final result = Future.value({
        'score': null,
        'level': 'local',
        'summary': '还没有配置可用的 AI 模型。本次回答已按本地练习保存，配置 AI 后可以重新评估。',
        'missedPoints': <String>[],
        'wrongPoints': <String>[],
        'errorPoints': <String>[],
        'improvedAnswer': '',
        'nextAction': '前往个人中心配置 AI，或继续本地练习',
        'aiUnavailable': true,
      });
      return (stream: const Stream.empty(), result: result);
    }

    // 取消之前的流
    _currentStreamSubscription?.cancel();
    
    final streamController = StreamController<String>();
    final completer = Completer<Map<String, dynamic>>();
    
    String fullContent = '';
    
    _currentStreamSubscription = _aiService.evaluateAnswerStream(
      config: config,
      topicTitle: question,
      mustHave: rubric?.mustHave ?? [],
      commonMistakes: rubric?.commonMistakes ?? [],
      userAnswer: userAnswer,
      language: '中文',
      imageBytes: imageBytes,
    ).listen(
      (chunk) {
        fullContent += chunk;
        streamController.add(chunk);
      },
      onDone: () {
        streamController.close();
        _currentStreamSubscription = null;
        // 解析完整内容
        final result = _parseStreamResult(fullContent);
        completer.complete(result);
      },
      onError: (error) {
        streamController.close();
        _currentStreamSubscription = null;
        completer.completeError(error);
      },
      cancelOnError: true,
    );
    
    return (stream: streamController.stream, result: completer.future);
  }

  /// 取消当前流式评估
  void cancelStreamEvaluation() {
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
  }

  Map<String, dynamic> _parseStreamResult(String content) {
    // 尝试从回复中提取 JSON
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      try {
        return json.decode(jsonMatch.group(0)!) as Map<String, dynamic>;
      } catch (_) {
        // JSON 解析失败，返回原始内容
      }
    }
    return {
      'score': 0,
      'level': 'unfamiliar',
      'summary': content,
      'missedPoints': <String>[],
      'wrongPoints': <String>[],
      'improvedAnswer': '',
      'nextAction': '重试',
    };
  }

  /// 通用流式聊天，用于 AI 改进等场景
  Stream<String> sendMessageStream(
    String userMessage, {
    String? systemPrompt,
  }) {
    final config = _defaultConfig ?? _configs.firstWhere(
      (c) => c.enabled,
      orElse: () => throw Exception('没有可用的 AI 配置'),
    );
    return _aiService.sendMessageStream(
      config: config,
      userMessage: userMessage,
      systemPrompt: systemPrompt,
    );
  }
}
