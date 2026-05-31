import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/ai_config.dart';

class AiService {
  /// 调用 OpenAI 兼容 API 评估用户回答（非流式）
  Future<Map<String, dynamic>> evaluateAnswer({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> commonMistakes,
    required String userAnswer,
    required String language,
    Uint8List? imageBytes,
  }) async {
    final systemPrompt = _buildSystemPrompt(mustHave, commonMistakes, language);

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

    throw Exception('evaluation_failed:${response.statusCode}');
  }

  /// 流式调用 OpenAI 兼容 API 评估用户回答
  Stream<String> evaluateAnswerStream({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> commonMistakes,
    required String userAnswer,
    required String language,
    Uint8List? imageBytes,
  }) async* {
    final systemPrompt = _buildSystemPrompt(mustHave, commonMistakes, language);

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
        throw Exception('evaluation_failed:${response.statusCode}');
      }

      // 处理 SSE 流
      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        
        // 处理完整的行
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 1);
          
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              return;
            }
            
            try {
              final jsonData = json.decode(data) as Map<String, dynamic>;
              final choices = jsonData['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null) {
                  yield content;
                }
              }
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }

  /// 构建用户消息内容，支持图片多模态
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

  String _buildSystemPrompt(List<String> mustHave, List<String> commonMistakes, String language) {
    return '''你是一个技术面试评估专家。请评估用户对知识点的回答。

评估维度：
1. 核心概念完整性 (40%)：是否覆盖标准要点
2. 表达准确性 (25%)：是否有明显错误或混淆
3. 面试表达质量 (20%)：是否像面试回答，结构是否清晰
4. 扩展深度 (15%)：是否能结合场景、优缺点、实践经验

标准要点：${mustHave.join('、')}
常见错误：${commonMistakes.join('、')}

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

  Map<String, dynamic> _parseEvaluationResult(String content) {
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
      'nextAction': 'retry',
    };
  }

  /// 测试 AI 配置连接
  Future<bool> testConnection(AiConfig config) async {
    try {
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
            {'role': 'user', 'content': 'Hi'},
          ],
          'max_tokens': 5,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 通过 Worker 代理调用 AI（Web 端用，避免 CORS）
  Future<Map<String, dynamic>> evaluateViaProxy({
    required String workerUrl,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> commonMistakes,
    required String userAnswer,
    required String apiKey,
    required String model,
    required String baseUrl,
    required String language,
  }) async {
    final url = '${workerUrl.replaceAll(RegExp(r'/+$'), '')}/ai/proxy';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'topicTitle': topicTitle,
        'mustHave': mustHave,
        'commonMistakes': commonMistakes,
        'userAnswer': userAnswer,
        'language': language,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('proxy_eval_failed:${response.statusCode}');
  }

  /// 通用流式聊天补全
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
        throw Exception('ai_request_failed:${response.statusCode}');
      }

      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') return;
            try {
              final jsonData = json.decode(data) as Map<String, dynamic>;
              final choices = jsonData['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null) yield content;
              }
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
