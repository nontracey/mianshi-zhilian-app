import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../models/ai_config.dart';
import 'app_log_service.dart';
import 'sensitive_data_redactor.dart';

class AiTestResult {
  final bool success;
  final String messageKey;
  final String detail;
  final int? statusCode;

  const AiTestResult({
    required this.success,
    required this.messageKey,
    this.detail = '',
    this.statusCode,
  });
}

class AiService {
  Future<Map<String, dynamic>> evaluateAnswer({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> goodToHave,
    required List<String> commonMistakes,
    Map<String, int>? scoreWeights,
    required String userAnswer,
    required String language,
    Uint8List? imageBytes,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      mustHave: mustHave,
      goodToHave: goodToHave,
      commonMistakes: commonMistakes,
      scoreWeights: scoreWeights,
      language: language,
    );
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: json.encode({
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': _buildUserContent(topicTitle, userAnswer, imageBytes),
          },
        ],
        'temperature': 0.3,
        'max_tokens': 2000,
      }),
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      final content =
          body['choices']?[0]?['message']?['content'] as String? ?? '';
      return _parseEvaluationResult(content);
    }

    _logAiFailure(
      config,
      'evaluate_answer',
      statusCode: response.statusCode,
      detail: response.body,
    );
    throw AiServiceException.fromResponse(response.statusCode, response.body);
  }

  Stream<String> evaluateAnswerStream({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> goodToHave,
    required List<String> commonMistakes,
    Map<String, int>? scoreWeights,
    required String userAnswer,
    required String language,
    Uint8List? imageBytes,
  }) async* {
    final systemPrompt = _buildSystemPrompt(
      mustHave: mustHave,
      goodToHave: goodToHave,
      commonMistakes: commonMistakes,
      scoreWeights: scoreWeights,
      language: language,
    );
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.body = json.encode({
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': _buildUserContent(topicTitle, userAnswer, imageBytes),
          },
        ],
        'temperature': 0.3,
        'max_tokens': 2000,
        'stream': true,
      });

      final response = await client.send(request);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        _logAiFailure(
          config,
          'evaluate_answer_stream',
          statusCode: response.statusCode,
          detail: body,
        );
        throw AiServiceException.fromResponse(response.statusCode, body);
      }

      yield* _decodeSseContent(response.stream);
    } finally {
      client.close();
    }
  }

  Future<AiTestResult> testTextConnection(AiConfig config) async {
    try {
      final url =
          '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: json.encode({
              'model': config.model,
              'messages': [
                {'role': 'user', 'content': 'Hi'},
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return const AiTestResult(
          success: true,
          messageKey: 'connection_success',
        );
      }
      _logAiFailure(
        config,
        'test_text_connection',
        statusCode: response.statusCode,
        detail: response.body,
      );
      final exception = AiServiceException.fromResponse(
        response.statusCode,
        response.body,
      );
      return AiTestResult(
        success: false,
        messageKey: exception.messageKey,
        detail: exception.safeDetail,
        statusCode: exception.statusCode,
      );
    } on TimeoutException catch (e) {
      unawaited(
        AppLog.warning(
          'AI text connection test timeout: ${_baseHost(config)} '
          'model=${config.model}',
          source: 'ai',
          error: e,
        ),
      );
      return const AiTestResult(success: false, messageKey: 'ai_test_timeout');
    } catch (e) {
      unawaited(
        AppLog.warning(
          'AI text connection test failed: ${_baseHost(config)} '
          'model=${config.model}',
          source: 'ai',
          error: e,
        ),
      );
      return AiTestResult(
        success: false,
        messageKey: 'ai_test_network_error',
        detail: _safeErrorDetail(e),
      );
    }
  }

  Future<bool> testConnection(AiConfig config) async =>
      (await testTextConnection(config)).success;

  /// 检查指定 AI 配置是否可用于文本生成
  bool isConfigAvailable(AiConfig? config) {
    return config != null && config.canEvaluate;
  }

  Future<AiTestResult> testAudioConnection(AiConfig config) async {
    if (config.audioMode == AiAudioMode.none) {
      return const AiTestResult(
        success: false,
        messageKey: 'audio_mode_not_enabled',
      );
    }
    try {
      final text = await transcribeAudio(
        config: config,
        audioBytes: _createSilentWav(),
      );
      return AiTestResult(
        success: true,
        messageKey: 'connection_success',
        detail: text,
      );
    } on AiServiceException catch (e) {
      return AiTestResult(
        success: false,
        messageKey: e.messageKey,
        detail: e.safeDetail,
        statusCode: e.statusCode,
      );
    } on TimeoutException catch (e) {
      unawaited(
        AppLog.warning(
          'AI audio connection test timeout: ${_baseHost(config)} '
          'model=${config.model} mode=${config.audioMode.name}',
          source: 'ai',
          error: e,
        ),
      );
      return const AiTestResult(success: false, messageKey: 'ai_test_timeout');
    } catch (e) {
      unawaited(
        AppLog.warning(
          'AI audio connection test failed: ${_baseHost(config)} '
          'model=${config.model} mode=${config.audioMode.name}',
          source: 'ai',
          error: e,
        ),
      );
      return AiTestResult(
        success: false,
        messageKey: 'ai_test_network_error',
        detail: _safeErrorDetail(e),
      );
    }
  }

  Future<String> transcribeAudio({
    required AiConfig config,
    required Uint8List audioBytes,
    String language = 'zh',
    String fileName = 'audio.wav',
  }) async {
    switch (config.audioMode) {
      case AiAudioMode.transcriptionEndpoint:
        return _transcribeViaEndpoint(
          config: config,
          audioBytes: audioBytes,
          language: language,
          fileName: fileName,
        );
      case AiAudioMode.chatAudioInput:
        return _transcribeViaChatAudio(
          config: config,
          audioBytes: audioBytes,
          language: language,
        );
      case AiAudioMode.none:
        throw const AiServiceException(messageKey: 'audio_mode_not_enabled');
    }
  }

  Stream<String> sendMessageStream({
    required AiConfig config,
    required String userMessage,
    String? systemPrompt,
  }) async* {
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final messages = <Map<String, String>>[];
    if (systemPrompt != null) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': userMessage});

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.body = json.encode({
        'model': config.model,
        'messages': messages,
        'temperature': 0.5,
        'max_tokens': 2000,
        'stream': true,
      });

      final response = await client.send(request);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        _logAiFailure(
          config,
          'send_message_stream',
          statusCode: response.statusCode,
          detail: body,
        );
        throw AiServiceException.fromResponse(response.statusCode, body);
      }

      yield* _decodeSseContent(response.stream);
    } finally {
      client.close();
    }
  }

  /// 使用指定 AI 配置发送文本消息并返回响应
  Future<String> sendMessage(String prompt, {required AiConfig config}) async {
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: json.encode({
            'model': config.model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.3,
            'max_tokens': 1000,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['choices']?[0]?['message']?['content'] as String? ?? '';
    }
    throw AiServiceException.fromResponse(response.statusCode, response.body);
  }

  Future<String> _transcribeViaEndpoint({
    required AiConfig config,
    required Uint8List audioBytes,
    required String language,
    required String fileName,
  }) async {
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/audio/transcriptions';
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer ${config.apiKey}';
    request.fields['model'] = config.model;
    request.fields['language'] = language;
    request.fields['response_format'] = 'text';
    request.fields['temperature'] = '0';
    request.files.add(
      http.MultipartFile.fromBytes('file', audioBytes, filename: fileName),
    );

    final client = http.Client();
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        _logAiFailure(
          config,
          'transcribe_endpoint',
          statusCode: response.statusCode,
          detail: response.body,
        );
        throw AiServiceException.fromResponse(
          response.statusCode,
          response.body,
        );
      }
      return response.body.trim();
    } finally {
      client.close();
    }
  }

  Future<String> _transcribeViaChatAudio({
    required AiConfig config,
    required Uint8List audioBytes,
    required String language,
  }) async {
    final url =
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: json.encode({
            'model': config.model,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text':
                        '请把这段技术面试练习音频逐字转写成$language文本。'
                        '保留技术名词、英文缩写和代码词，不要总结、不要补全、不要解释。'
                        '如果没有清晰语音，只返回空字符串。',
                  },
                  {
                    'type': 'input_audio',
                    'input_audio': {
                      'data': base64Encode(audioBytes),
                      'format': 'wav',
                    },
                  },
                ],
              },
            ],
            'temperature': 0,
            'max_tokens': 200,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      _logAiFailure(
        config,
        'transcribe_chat_audio',
        statusCode: response.statusCode,
        detail: response.body,
      );
      throw AiServiceException.fromResponse(response.statusCode, response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final message = body['choices']?[0]?['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is String) return content.trim();
    if (content is List) {
      return content
          .map((item) {
            if (item is Map<String, dynamic>) {
              return item['text']?.toString() ?? '';
            }
            return item.toString();
          })
          .where((text) => text.trim().isNotEmpty)
          .join('\n')
          .trim();
    }
    return '';
  }

  Stream<String> _decodeSseContent(Stream<List<int>> stream) async* {
    String buffer = '';
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n')) {
        final index = buffer.indexOf('\n');
        final line = buffer.substring(0, index).trim();
        buffer = buffer.substring(index + 1);
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6);
        if (data == '[DONE]') return;
        try {
          final jsonData = json.decode(data) as Map<String, dynamic>;
          final choices = jsonData['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null) yield content;
        } catch (_) {}
      }
    }
  }

  dynamic _buildUserContent(
    String topicTitle,
    String userAnswer,
    Uint8List? imageBytes,
  ) {
    final text = '知识点：$topicTitle\n\n我的回答：\n$userAnswer';
    if (imageBytes == null || imageBytes.isEmpty) return text;

    final base64Image = base64Encode(imageBytes);
    return [
      {'type': 'text', 'text': text},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
      },
    ];
  }

  String _buildSystemPrompt({
    required List<String> mustHave,
    required List<String> goodToHave,
    required List<String> commonMistakes,
    required Map<String, int>? scoreWeights,
    required String language,
  }) {
    final weights = _normalizeScoreWeights(scoreWeights);
    return '''你是一个技术面试评估专家。请评估用户对知识点的回答。

评估维度：
1. 核心概念完整性 (${weights.coverage}%)：是否覆盖标准要点
2. 表达准确性 (${weights.accuracy}%)：是否有明显错误或混淆
3. 面试表达质量 (${weights.expression}%)：是否像面试回答，结构是否清晰
4. 扩展深度 (${weights.depth}%)：是否能结合场景、优缺点、实践经验

标准要点：${mustHave.isEmpty ? '无' : mustHave.join('、')}
加分要点：${goodToHave.isEmpty ? '无' : goodToHave.join('、')}
常见错误：${commonMistakes.isEmpty ? '无' : commonMistakes.join('、')}

请用$language回答，并以如下 JSON 格式输出：
{
  "score": 86,
  "level": "skilled",
  "summary": "整体理解正确，但可以补充...",
  "missedPoints": ["遗漏要点1"],
  "wrongPoints": ["错误点1"],
  "improvedAnswer": "面试时可以这样回答：...",
  "nextAction": "进入下一知识点"
}

score 范围 0-100，level 为 skilled(>=85)/familiar(>=60)/unfamiliar(<60)。''';
  }

  _EvaluationWeights _normalizeScoreWeights(Map<String, int>? raw) {
    int pick(String key, int fallback, [List<String> aliases = const []]) {
      var value = raw?[key];
      for (final alias in aliases) {
        value ??= raw?[alias];
      }
      if (value == null || value <= 0) return fallback;
      return value;
    }

    return _EvaluationWeights(
      coverage: pick('coverage', 40),
      accuracy: pick('accuracy', 25),
      expression: pick('interviewExpression', 20, ['expression']),
      depth: pick('depth', 15, ['goodToHave']),
    );
  }

  Map<String, dynamic> _parseEvaluationResult(String content) {
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      try {
        return _normalizeEvaluationResult(
          json.decode(jsonMatch.group(0)!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return {
      'score': null,
      'level': 'local',
      'summary': content.isNotEmpty
          ? content
          : L10n.get('evaluation_parse_failed', L10n.currentLanguage),
      'missedPoints': <String>[],
      'wrongPoints': <String>[],
      'improvedAnswer': '',
      'nextAction': L10n.get('retry', L10n.currentLanguage),
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

  Uint8List _createSilentWav() {
    final data = ByteData(48);
    data.setUint8(0, 0x52);
    data.setUint8(1, 0x49);
    data.setUint8(2, 0x46);
    data.setUint8(3, 0x46);
    data.setUint32(4, 40, Endian.little);
    data.setUint8(8, 0x57);
    data.setUint8(9, 0x41);
    data.setUint8(10, 0x56);
    data.setUint8(11, 0x45);
    data.setUint8(12, 0x66);
    data.setUint8(13, 0x6D);
    data.setUint8(14, 0x74);
    data.setUint8(15, 0x20);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 16000, Endian.little);
    data.setUint32(28, 32000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    data.setUint8(36, 0x64);
    data.setUint8(37, 0x61);
    data.setUint8(38, 0x74);
    data.setUint8(39, 0x61);
    data.setUint32(40, 4, Endian.little);
    data.setInt16(44, 0, Endian.little);
    data.setInt16(46, 0, Endian.little);
    return data.buffer.asUint8List();
  }

  static String _safeErrorDetail(Object error) {
    final text = SensitiveDataRedactor.redact(error.toString());
    return text.length > 160 ? '${text.substring(0, 160)}...' : text;
  }

  static void _logAiFailure(
    AiConfig config,
    String operation, {
    required int statusCode,
    required String detail,
  }) {
    unawaited(
      AppLog.warning(
        'AI $operation failed: HTTP $statusCode ${_baseHost(config)} '
        'model=${config.model} audioMode=${config.audioMode.name}',
        source: 'ai',
        error: _safeBodyDetail(detail),
      ),
    );
  }

  static String _baseHost(AiConfig config) {
    final uri = Uri.tryParse(config.baseUrl);
    return uri?.host.isNotEmpty == true ? uri!.host : 'custom_endpoint';
  }

  static String _safeBodyDetail(String body) {
    if (body.isEmpty) return '';
    final detail = AiServiceException._extractSafeDetail(body);
    if (detail.isNotEmpty) return detail;
    return body.length > 240 ? '${body.substring(0, 240)}...' : body;
  }
}

class _EvaluationWeights {
  const _EvaluationWeights({
    required this.coverage,
    required this.accuracy,
    required this.expression,
    required this.depth,
  });

  final int coverage;
  final int accuracy;
  final int expression;
  final int depth;
}

class AiServiceException implements Exception {
  final String messageKey;
  final int? statusCode;
  final String safeDetail;

  const AiServiceException({
    required this.messageKey,
    this.statusCode,
    this.safeDetail = '',
  });

  factory AiServiceException.fromResponse(int statusCode, String body) {
    final detail = _extractSafeDetail(body);
    if (statusCode == 401 || statusCode == 403) {
      return AiServiceException(
        messageKey: 'ai_test_auth_error',
        statusCode: statusCode,
        safeDetail: detail,
      );
    }
    if (statusCode == 404) {
      return AiServiceException(
        messageKey: 'ai_test_not_found',
        statusCode: statusCode,
        safeDetail: detail,
      );
    }
    if (statusCode == 429) {
      return AiServiceException(
        messageKey: 'ai_test_rate_limited',
        statusCode: statusCode,
        safeDetail: detail,
      );
    }
    if (detail.toLowerCase().contains('model')) {
      return AiServiceException(
        messageKey: 'ai_test_model_error',
        statusCode: statusCode,
        safeDetail: detail,
      );
    }
    return AiServiceException(
      messageKey: 'ai_test_http_error',
      statusCode: statusCode,
      safeDetail: detail,
    );
  }

  static String _extractSafeDetail(String body) {
    if (body.isEmpty) return '';
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return _redact(error['message']?.toString() ?? '');
        }
        return _redact(decoded['message']?.toString() ?? '');
      }
    } catch (_) {}
    final trimmed = body.length > 240 ? '${body.substring(0, 240)}...' : body;
    return _redact(trimmed);
  }

  static String _redact(String text) {
    return SensitiveDataRedactor.redact(text);
  }

  @override
  String toString() =>
      statusCode == null ? messageKey : '$messageKey:$statusCode';
}
