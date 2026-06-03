import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// OpenAI Chat Completions 格式的流式语音转写服务
///
/// 使用 Chat Completions API 的 input_audio 格式发送音频，
/// 通过 SSE (Server-Sent Events) 流式接收转写结果。
///
/// 兼容所有支持此格式的 OpenAI 兼容 API，如：
/// - Xiaomi MiMo (mimo-v2.5-asr)
/// - OpenAI gpt-audio-1.5
/// - 以及其他使用 Chat Completions + input_audio 格式的服务
class WhisperStreamSttService {
  /// 单次流式转写：发送音频到 Chat Completions API，返回 SSE 文本流
  ///
  /// [audioBytes] 音频文件内容（WAV 格式）
  /// [baseUrl] API 基地址，如 https://api.xiaomimimo.com/v1
  /// [apiKey] API 密钥
  /// [model] 模型名，如 mimo-v2.5-asr / gpt-audio-1.5
  /// [language] 语言代码，如 zh、en、auto
  ///
  /// 返回一个 `Stream<String>`，每段新识别的文本增量
  Stream<String> transcribeStream({
    required Uint8List audioBytes,
    required String baseUrl,
    required String apiKey,
    String model = 'mimo-v2.5-asr',
    String language = 'zh',
  }) async* {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$cleanBase/chat/completions';

    final audioBase64 = base64Encode(audioBytes);

    final body = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {
                'data': audioBase64,
                'format': 'wav',
              },
            },
          ],
        },
      ],
      'stream': true,
    };

    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request).timeout(
        const Duration(seconds: 30),
      );

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Stream transcription failed: HTTP ${streamedResponse.statusCode}\n'
          'URL: $url\n'
          'Response: ${errorBody.length > 200 ? '${errorBody.substring(0, 200)}...' : errorBody}',
        );
      }

      // 解析 SSE 流
      String buffer = '';
      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 60))) {
        buffer += chunk;

        // 按行分割 SSE 事件
        while (buffer.contains('\n')) {
          final newlineIdx = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIdx).trim();
          buffer = buffer.substring(newlineIdx + 1);

          if (line.isEmpty) continue;
          if (!line.startsWith('data: ')) continue;

          final data = line.substring(6); // 去掉 "data: " 前缀
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final delta = (choices[0] as Map<String, dynamic>)['delta'];
            if (delta == null) continue;

            final content = (delta as Map<String, dynamic>)['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield content;
            }
          } catch (_) {
            // 跳过无法解析的 SSE 行
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
