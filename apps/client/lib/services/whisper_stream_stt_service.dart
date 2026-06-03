import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Whisper 语音转文字服务
///
/// 只做一件事：调用标准 Whisper /audio/transcriptions 端点，
/// 把音频转成文字。不涉及 Chat Completions 或其他 AI 模型。
///
/// 如果用户需要基于 Chat Completions 的语音识别（如 MiMo ASR），
/// 应通过 AI 配置（AiConfig usageTag='stt'）来使用，而非本服务。
class WhisperStreamSttService {
  /// 单次转写：发送音频到 Whisper /audio/transcriptions 端点
  ///
  /// 返回识别出的文字内容。如果识别结果为空则不 yield。
  Stream<String> transcribeStream({
    required Uint8List audioBytes,
    required String baseUrl,
    required String apiKey,
    String model = 'whisper-1',
    String language = 'zh',
  }) async* {
    final text = await _transcribe(
      audioBytes: audioBytes,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      language: language,
    );
    if (text.isNotEmpty) yield text;
  }

  /// 标准 /audio/transcriptions 转写
  Future<String> _transcribe({
    required Uint8List audioBytes,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String language,
  }) async {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$cleanBase/audio/transcriptions';

    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = model;
    request.fields['language'] = language;
    request.fields['response_format'] = 'text';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: 'audio.wav',
      ),
    );

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request).timeout(
        const Duration(seconds: 30),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 429) {
        // 额度耗尽 — 明确提示
        String detail = 'API 额度耗尽';
        try {
          final errJson = jsonDecode(response.body) as Map<String, dynamic>;
          final errMsg = errJson['error']?['message'] ?? '';
          if (errMsg.isNotEmpty) detail = errMsg;
        } catch (_) {}
        throw WhisperApiException(
          detail,
          url: url,
          statusCode: 429,
          body: response.body,
        );
      }

      if (response.statusCode != 200) {
        final errorBody = response.body.length > 300
            ? '${response.body.substring(0, 300)}...'
            : response.body;
        throw WhisperApiException(
          '/audio/transcriptions 失败: HTTP ${response.statusCode}',
          url: url,
          statusCode: response.statusCode,
          body: errorBody,
        );
      }

      return response.body.trim();
    } finally {
      client.close();
    }
  }

  /// 测试 API 连通性
  ///
  /// 返回 [WhisperTestResult] 含是否可达和错误详情。
  /// 用一段极短静音 WAV 请求 /audio/transcriptions：
  /// - 200 → 可达
  /// - 429 → 可达但额度耗尽
  /// - 404 → 端点不存在（可能不是标准 Whisper API）
  /// - 其他/超时 → 不可达
  Future<WhisperTestResult> testConnection({
    required String baseUrl,
    required String apiKey,
    String model = 'whisper-1',
  }) async {
    final silentWav = _createSilentWav();

    // 直接测试 /audio/transcriptions
    try {
      await _transcribe(
        audioBytes: silentWav,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        language: 'zh',
      );
      return const WhisperTestResult(
        reachable: true,
        detail: null,
      );
    } on WhisperApiException catch (e) {
      if (e.statusCode == 429) {
        // 额度耗尽但端点可达
        return WhisperTestResult(
          reachable: true,
          detail: 'API 端点可达，但额度已耗尽 (${e.message})。'
              '\n请到 API 平台充值后再试。',
        );
      }
      if (e.statusCode == 404) {
        // 端点不存在，不是标准 Whisper API
        // 再检查一下网络是否可达
        final networkOk = await _checkNetworkReachable(baseUrl, apiKey);
        if (networkOk) {
          return WhisperTestResult(
            reachable: false,
            detail: '网络可达，但 /audio/transcriptions 端点不存在。'
                '\n\n此 API 不支持标准 Whisper 语音转写格式。'
                '\n如需使用 Chat Completions 类语音模型（如 MiMo ASR），'
                '\n请在 AI 配置中添加，标记用途为"语音识别"。',
          );
        }
        return WhisperTestResult(
          reachable: false,
          detail: '/audio/transcriptions 端点不存在 (404)。',
        );
      }
      return WhisperTestResult(
        reachable: false,
        detail: 'HTTP ${e.statusCode}: ${e.message}',
      );
    } catch (e) {
      final msg = e.toString();
      // 检查网络是否可达
      final networkOk = await _checkNetworkReachable(baseUrl, apiKey);
      if (networkOk) {
        return WhisperTestResult(
          reachable: false,
          detail: '网络可达，但 API 不支持语音转写。'
              '\n$msg'
              '\n\n提示: 请确认 Base URL 指向标准 Whisper API 端点'
              '\n(如 https://api.openai.com/v1)',
        );
      }
      return WhisperTestResult(
        reachable: false,
        detail: '无法连接到 API: ${msg.length > 100 ? '${msg.substring(0, 100)}...' : msg}',
      );
    }
  }

  /// 检查 API 网络是否可达（GET /models）
  Future<bool> _checkNetworkReachable(String baseUrl, String apiKey) async {
    try {
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await http.get(
        Uri.parse('$cleanBase/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 401;
    } catch (_) {
      return false;
    }
  }

  /// 创建极小的静音 WAV（0.25s mono 16-bit 16kHz）
  Uint8List _createSilentWav() {
    final numSamples = 4000; // 0.25s at 16kHz
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final fileSize = 44 + dataSize;
    final wav = Uint8List(fileSize);
    final data = ByteData.view(wav.buffer);

    // RIFF header
    data.setUint8(0, 0x52); data.setUint8(1, 0x49);
    data.setUint8(2, 0x46); data.setUint8(3, 0x46);
    data.setUint32(4, fileSize - 8, Endian.little);
    data.setUint8(8, 0x57); data.setUint8(9, 0x41);
    data.setUint8(10, 0x56); data.setUint8(11, 0x45);
    // fmt chunk
    data.setUint8(12, 0x66); data.setUint8(13, 0x6D);
    data.setUint8(14, 0x74); data.setUint8(15, 0x20);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, 16000, Endian.little); // sample rate
    data.setUint32(28, 32000, Endian.little); // byte rate
    data.setUint16(32, 2, Endian.little); // block align
    data.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    data.setUint8(36, 0x64); data.setUint8(37, 0x61);
    data.setUint8(38, 0x74); data.setUint8(39, 0x61);
    data.setUint32(40, dataSize, Endian.little);
    // silence (all zeros, already initialized)

    return wav;
  }
}

/// Whisper API 测试结果
class WhisperTestResult {
  final bool reachable;
  final String? detail; // 错误详情或提示

  const WhisperTestResult({
    required this.reachable,
    this.detail,
  });
}

/// Whisper API 异常（包含诊断信息）
class WhisperApiException implements Exception {
  final String message;
  final String? url;
  final int? statusCode;
  final String? body;

  const WhisperApiException(
    this.message, {
    this.url,
    this.statusCode,
    this.body,
  });

  @override
  String toString() => message;
}
