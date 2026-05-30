import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Whisper 兼容 STT 服务
///
/// 支持任何 OpenAI Whisper 兼容 API（如 OpenAI、Groq、本地 whisper-server）
class WhisperSttService {
  /// 将音频字节发送到 Whisper API 进行转写
  ///
  /// [audioBytes] 音频文件内容（WAV/MP3/WebM/M4A 等）
  /// [baseUrl] API 基地址，如 https://api.openai.com/v1
  /// [apiKey] API 密钥
  /// [model] 模型名称，默认 whisper-1
  /// [language] 语言代码，如 zh、en
  /// [fileName] 文件名（用于 MIME 类型推断）
  Future<String> transcribe({
    required Uint8List audioBytes,
    required String baseUrl,
    required String apiKey,
    String model = 'whisper-1',
    String language = 'zh',
    String fileName = 'audio.wav',
  }) async {
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/audio/transcriptions';

    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = model;
    request.fields['language'] = language;
    request.fields['response_format'] = 'text';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Whisper 转写失败: ${response.statusCode} ${response.body}');
    }

    return response.body.trim();
  }

  /// 测试 Whisper API 连接
  Future<bool> testConnection({
    required String baseUrl,
    required String apiKey,
    String model = 'whisper-1',
  }) async {
    try {
      // 发送一个极小的静音 WAV 文件进行测试
      final silentWav = _createSilentWav();
      await transcribe(
        audioBytes: silentWav,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建一个极小的静音 WAV 文件用于连接测试
  Uint8List _createSilentWav() {
    // 最小 WAV: 44 bytes header + 4 bytes data (0.0002s mono 16-bit 16kHz)
    final data = ByteData(48);
    // RIFF header
    data.setUint8(0, 0x52); // R
    data.setUint8(1, 0x49); // I
    data.setUint8(2, 0x46); // F
    data.setUint8(3, 0x46); // F
    data.setUint32(4, 40, Endian.little); // file size - 8
    data.setUint8(8, 0x57); // W
    data.setUint8(9, 0x41); // A
    data.setUint8(10, 0x56); // V
    data.setUint8(11, 0x45); // E
    // fmt chunk
    data.setUint8(12, 0x66); // f
    data.setUint8(13, 0x6D); // m
    data.setUint8(14, 0x74); // t
    data.setUint8(15, 0x20); // space
    data.setUint32(16, 16, Endian.little); // chunk size
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, 16000, Endian.little); // sample rate
    data.setUint32(28, 32000, Endian.little); // byte rate
    data.setUint16(32, 2, Endian.little); // block align
    data.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    data.setUint8(36, 0x64); // d
    data.setUint8(37, 0x61); // a
    data.setUint8(38, 0x74); // t
    data.setUint8(39, 0x61); // a
    data.setUint32(40, 4, Endian.little); // data size
    data.setInt16(44, 0, Endian.little); // silence sample 1
    data.setInt16(46, 0, Endian.little); // silence sample 2

    return data.buffer.asUint8List();
  }
}
