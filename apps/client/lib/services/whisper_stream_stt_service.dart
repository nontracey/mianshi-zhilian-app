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

  /// 测试 API 连通性：发送极小的静音 WAV，验证端点是否可达
  Future<bool> testConnection({
    required String baseUrl,
    required String apiKey,
    String model = 'mimo-v2.5-asr',
  }) async {
    try {
      // 最小 WAV: 44 bytes header + 4 bytes data
      final silentWav = Uint8List(48);
      final data = ByteData.view(silentWav.buffer);
      data.setUint8(0, 0x52); data.setUint8(1, 0x49); data.setUint8(2, 0x46); data.setUint8(3, 0x46);
      data.setUint32(4, 40, Endian.little);
      data.setUint8(8, 0x57); data.setUint8(9, 0x41); data.setUint8(10, 0x56); data.setUint8(11, 0x45);
      data.setUint8(12, 0x66); data.setUint8(13, 0x6D); data.setUint8(14, 0x74); data.setUint8(15, 0x20);
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little); data.setUint16(22, 1, Endian.little);
      data.setUint32(24, 16000, Endian.little); data.setUint32(28, 32000, Endian.little);
      data.setUint16(32, 2, Endian.little); data.setUint16(34, 16, Endian.little);
      data.setUint8(36, 0x64); data.setUint8(37, 0x61); data.setUint8(38, 0x74); data.setUint8(39, 0x61);
      data.setUint32(40, 4, Endian.little);
      data.setInt16(44, 0, Endian.little); data.setInt16(46, 0, Endian.little);

      // 接收至少一个 chunk 就算连通
      final stream = transcribeStream(
        audioBytes: silentWav,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
      await for (final _ in stream) {
        return true;
      }
      return true; // 空流也算连通（有些 API 对静音返回空）
    } catch (_) {
      return false;
    }
  }
}
