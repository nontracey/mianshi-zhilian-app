import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_config.dart';

class AiService {
  /// 调用 OpenAI 兼容 API 评估用户回答
  Future<Map<String, dynamic>> evaluateAnswer({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> commonMistakes,
    required String userAnswer,
    required String language,
  }) async {
    final systemPrompt = '''你是一个技术面试评估专家。请评估用户对知识点的回答。

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

    final url = '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
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
          {'role': 'user', 'content': '知识点：$topicTitle\n\n我的回答：\n$userAnswer'},
        ],
        'temperature': 0.3,
        'max_tokens': 2000,
      }),
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content'] as String? ?? '';
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

    throw Exception('AI 评估失败: ${response.statusCode} ${response.body}');
  }

  /// 测试 AI 配置连接
  Future<bool> testConnection(AiConfig config) async {
    try {
      final url = '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
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
    throw Exception('AI 代理评估失败: ${response.statusCode}');
  }
}
