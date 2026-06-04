import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 模型文件定义
class ModelFile {
  const ModelFile(this.relativePath, this.url, [this.sizeBytes]);

  /// 模型存储目录的相对路径
  final String relativePath;

  /// 下载 URL
  final String url;

  /// 预期文件大小（字节），用于校验
  final int? sizeBytes;
}

/// 引擎模型配置
class OnDeviceModelConfig {
  const OnDeviceModelConfig({
    required this.id,
    required this.displayName,
    required this.files,
    this.estimatedSizeMb,
  });

  final String id;
  final String displayName;
  final List<ModelFile> files;
  final int? estimatedSizeMb;
}

/// sherpa_onnx 常用模型配置
class KnownModels {
  KnownModels._();

  static final senseVoice = OnDeviceModelConfig(
    id: 'sense-voice',
    displayName: 'SenseVoice 小型多语言',
    estimatedSizeMb: 41,
    files: const [
      ModelFile(
        'model.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/model.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/tokens.txt',
      ),
    ],
  );

  static final whisperBase = OnDeviceModelConfig(
    id: 'whisper-base',
    displayName: 'Whisper Base',
    estimatedSizeMb: 150,
    files: const [
      ModelFile(
        'encoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base/encoder.int8.onnx',
      ),
      ModelFile(
        'decoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base/decoder.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base/tokens.txt',
      ),
    ],
  );

  static final whisperTiny = OnDeviceModelConfig(
    id: 'whisper-tiny',
    displayName: 'Whisper Tiny',
    estimatedSizeMb: 78,
    files: const [
      ModelFile(
        'encoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny/encoder.int8.onnx',
      ),
      ModelFile(
        'decoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny/decoder.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny/tokens.txt',
      ),
    ],
  );

  static final whisperSmall = OnDeviceModelConfig(
    id: 'whisper-small',
    displayName: 'Whisper Small',
    estimatedSizeMb: 490,
    files: const [
      ModelFile(
        'encoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small/encoder.int8.onnx',
      ),
      ModelFile(
        'decoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small/decoder.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small/tokens.txt',
      ),
    ],
  );

  static final whisperMedium = OnDeviceModelConfig(
    id: 'whisper-medium',
    displayName: 'Whisper Medium',
    estimatedSizeMb: 1540,
    files: const [
      ModelFile(
        'encoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium/encoder.int8.onnx',
      ),
      ModelFile(
        'decoder.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium/decoder.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium/tokens.txt',
      ),
    ],
  );

  static final paraformer = OnDeviceModelConfig(
    id: 'paraformer',
    displayName: 'Paraformer 在线流式',
    estimatedSizeMb: 41,
    files: const [
      ModelFile(
        'model.int8.onnx',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2023-09-14/model.int8.onnx',
      ),
      ModelFile(
        'tokens.txt',
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2023-09-14/tokens.txt',
      ),
    ],
  );
}

/// 模型下载状态回调
typedef OnDownloadProgress = void Function(int received, int total);

/// 通用模型下载器
class ModelDownloader {
  ModelDownloader._();

  /// 获取模型存储根目录
  static Future<Directory> getStorageDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/sherpa_onnx_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取指定模型配置的存储目录
  static Future<Directory> getModelDir(String modelId) async {
    final root = await getStorageDir();
    final dir = Directory('${root.path}/$modelId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 检查模型是否已下载完整
  static Future<bool> isModelReady(OnDeviceModelConfig config) async {
    final dir = await getModelDir(config.id);
    for (final file in config.files) {
      final f = File('${dir.path}/${file.relativePath}');
      if (!await f.exists()) return false;
      if (file.sizeBytes != null && await f.length() != file.sizeBytes) {
        return false;
      }
    }
    return true;
  }

  /// 获取已下载模型的文件大小（字节），null 表示未下载
  static Future<int?> getModelSize(String modelId) async {
    final dir = await getModelDir(modelId);
    final files = dir.listSync().whereType<File>().toList();
    if (files.isEmpty) return null;
    int total = 0;
    for (final f in files) {
      total += await f.length();
    }
    return total;
  }

  /// 删除整个模型
  static Future<void> deleteModel(String modelId) async {
    final dir = await getModelDir(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 下载指定模型，逐文件下载
  static Future<void> downloadModel({
    required OnDeviceModelConfig config,
    OnDownloadProgress? onProgress,
    String? mirrorBaseUrl,
  }) async {
    final dir = await getModelDir(config.id);
    int totalReceived = 0;
    int totalSize = 0;

    // 预计算总大小（如果有 sizeBytes）
    for (final file in config.files) {
      if (file.sizeBytes != null) {
        totalSize += file.sizeBytes!;
      }
    }

    for (final file in config.files) {
      final destPath = '${dir.path}/${file.relativePath}';
      final destDir = Directory(destPath.substring(0, destPath.lastIndexOf('/')));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final url = _resolveUrl(file.url, mirrorBaseUrl);
      final response = await http.Client().send(http.Request('GET', Uri.parse(url)));

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download ${file.relativePath}: HTTP ${response.statusCode}',
        );
      }

      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          totalReceived += chunk.length;
          if (file.sizeBytes != null) {
            totalSize = _updateTotalSize(config, totalSize, file.sizeBytes!);
          }
          onProgress?.call(totalReceived, totalSize > 0 ? totalSize : totalReceived);
        }
      } finally {
        await sink.close();
      }
    }
  }

  static String _resolveUrl(String originalUrl, String? mirrorBaseUrl) {
    if (mirrorBaseUrl == null || mirrorBaseUrl.isEmpty) return originalUrl;

    // 将 GitHub release URL 替换为镜像 URL
    // https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/... -> mirror/asr-models/...
    final releasePrefix = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/';
    if (originalUrl.startsWith(releasePrefix)) {
      final relativePath = originalUrl.substring(releasePrefix.length);
      return '${mirrorBaseUrl.replaceAll(RegExp(r'/$'), '')}/$relativePath';
    }
    return originalUrl;
  }

  static int _updateTotalSize(OnDeviceModelConfig config, int currentTotal, int fileSize) {
    // 如果 totalSize 是估算的（未使用 sizeBytes），这里通过已知 sizeBytes 更新
    if (currentTotal == 0) {
      int total = 0;
      for (final f in config.files) {
        total += f.sizeBytes ?? 0;
      }
      return total > 0 ? total : currentTotal;
    }
    return currentTotal;
  }
}