import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 模型文件定义（仅用于 isModelReady 检查）
class ModelFile {
  const ModelFile(this.relativePath, [this.sizeBytes]);

  /// 模型存储目录的相对路径
  final String relativePath;

  /// 预期文件大小（字节），用于校验
  final int? sizeBytes;
}

/// 引擎模型配置
class OnDeviceModelConfig {
  const OnDeviceModelConfig({
    required this.id,
    required this.displayName,
    required this.files,
    required this.archiveUrl,
    this.archiveSizeBytes,
    this.estimatedSizeMb,
  });

  final String id;
  final String displayName;
  final List<ModelFile> files;
  final String archiveUrl;
  final int? archiveSizeBytes;
  final int? estimatedSizeMb;

  /// 下载所需的最小磁盘空间（archive 解压后约 2x 空间）
  int get requiredDiskBytes {
    final archive = archiveSizeBytes ?? (estimatedSizeMb != null
        ? estimatedSizeMb! * 1024 * 1024
        : 100 * 1024 * 1024);
    // archive + decompressed (保守估计 3x)
    return archive * 3;
  }
}

/// sherpa_onnx 常用模型配置
class KnownModels {
  KnownModels._();

  static final senseVoice = OnDeviceModelConfig(
    id: 'sense-voice',
    displayName: 'SenseVoice 小型多语言',
    estimatedSizeMb: 155,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
    archiveSizeBytes: 163_002_883,
    files: const [
      ModelFile('model.int8.onnx'),
      ModelFile('tokens.txt'),
    ],
  );

  static final whisperBase = OnDeviceModelConfig(
    id: 'whisper-base',
    displayName: 'Whisper Base',
    estimatedSizeMb: 198,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
    archiveSizeBytes: 207_557_382,
    files: const [
      ModelFile('encoder.int8.onnx'),
      ModelFile('decoder.int8.onnx'),
      ModelFile('tokens.txt'),
    ],
  );

  static final whisperTiny = OnDeviceModelConfig(
    id: 'whisper-tiny',
    displayName: 'Whisper Tiny',
    estimatedSizeMb: 111,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
    archiveSizeBytes: 116_204_861,
    files: const [
      ModelFile('encoder.int8.onnx'),
      ModelFile('decoder.int8.onnx'),
      ModelFile('tokens.txt'),
    ],
  );

  static final whisperSmall = OnDeviceModelConfig(
    id: 'whisper-small',
    displayName: 'Whisper Small',
    estimatedSizeMb: 610,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2',
    archiveSizeBytes: 639_387_718,
    files: const [
      ModelFile('encoder.int8.onnx'),
      ModelFile('decoder.int8.onnx'),
      ModelFile('tokens.txt'),
    ],
  );

  static final whisperMedium = OnDeviceModelConfig(
    id: 'whisper-medium',
    displayName: 'Whisper Medium',
    estimatedSizeMb: 1842,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium.tar.bz2',
    archiveSizeBytes: 1_931_372_882,
    files: const [
      ModelFile('encoder.int8.onnx'),
      ModelFile('decoder.int8.onnx'),
      ModelFile('tokens.txt'),
    ],
  );

  static final paraformer = OnDeviceModelConfig(
    id: 'paraformer',
    displayName: 'Paraformer 离线小型',
    estimatedSizeMb: 74,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2',
    archiveSizeBytes: 77_920_048,
    files: const [
      ModelFile('model.int8.onnx'),
      ModelFile('tokens.txt'),
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
    // 递归统计所有文件大小
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total > 0 ? total : null;
  }

  /// 删除整个模型
  static Future<void> deleteModel(String modelId) async {
    final dir = await getModelDir(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// GitHub 代理镜像 URL 列表（按优先级排序）
  ///
  /// ghfast.top 在国内可直接访问 GitHub release 资源。
  /// 如果 ghfast.top 失效，可在此追加新的镜像地址。
  static const _mirrorPrefixes = [
    'https://ghfast.top',
  ];

  /// 下载指定模型（下载 .tar.bz2 存档并解压到模型目录）
  ///
  /// 磁盘安全策略：
  /// - 先下载存档到系统临时目录（流式写入，避免 OOM）
  /// - 支持断点续传：部分下载的临时文件以 `model_{modelId}_download.part`
  ///   命名留存，下次重试自动从断点继续（需服务器支持 Range 头）
  /// - 从临时文件读取并解压
  /// - 成功后清理临时文件
  ///
  /// 自动回退：尝试原始 GitHub release URL 失败时，自动用 ghfast.top 镜像重试。
  /// 国内/国外用户均可使用：国外走原始 URL，国内自动回退到 ghfast.top 镜像。
  static Future<void> downloadModel({
    required OnDeviceModelConfig config,
    OnDownloadProgress? onProgress,
    String? mirrorBaseUrl,
  }) async {
    final modelDir = await getModelDir(config.id);

    // 清理已有文件（修复旧版本提取到子目录的损坏状态）
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    await modelDir.create(recursive: true);

    // 1. 下载 .tar.bz2 存档到临时文件
    final tempFile = await _downloadArchiveToTemp(
      archiveUrl: config.archiveUrl,
      identifier: config.id,
      mirrorBaseUrl: mirrorBaseUrl,
      archiveSizeBytes: config.archiveSizeBytes,
      onProgress: onProgress,
    );

    try {
      // 2. 读取临时文件到内存用于 BZip2 解压
      onProgress?.call(0, config.archiveSizeBytes ?? 1);
      final archiveBytes = await tempFile.readAsBytes();

      // 3. BZip2 解压
      final List<int> tarBytes;
      try {
        tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
      } catch (e) {
        throw HttpException('BZip2 decompression failed: $e');
      }

      // 4. Tar 解压到模型目录
      //
      // sherpa-onnx 存档总是包含一个版本号子目录（如
      // sherpa-onnx-sense-voice-...-int8-2024-07-17/），
      // 提取时需要剥离公共顶层目录，使文件直接放在模型根目录。
      try {
        final archive = TarDecoder().decodeBytes(tarBytes);
        final fileEntries = archive.where((e) => e.isFile).toList();
        if (fileEntries.isEmpty) {
          throw HttpException('Archive is empty or contains no files');
        }

        // 检测所有文件条目的公共顶层目录前缀
        String? commonTopPrefix;
        for (final entry in fileEntries) {
          final slashPos = entry.name.indexOf('/');
          if (slashPos == -1) {
            commonTopPrefix = null;
            break;
          }
          final prefix = entry.name.substring(0, slashPos);
          if (commonTopPrefix == null) {
            commonTopPrefix = prefix;
          } else if (commonTopPrefix != prefix) {
            commonTopPrefix = null;
            break;
          }
        }

        int extractedCount = 0;
        for (final entry in fileEntries) {
          final relativeName = (commonTopPrefix != null &&
                  entry.name.startsWith('$commonTopPrefix/'))
              ? entry.name.substring(commonTopPrefix.length + 1)
              : entry.name;
          if (relativeName.isEmpty) continue;

          final destPath = '${modelDir.path}/$relativeName';
          final destDir = Directory(
            destPath.substring(0, destPath.lastIndexOf('/')),
          );
          if (!await destDir.exists()) {
            await destDir.create(recursive: true);
          }
          await File(destPath).writeAsBytes(
            entry.content is Uint8List
                ? entry.content as Uint8List
                : Uint8List.fromList(entry.content),
          );
          extractedCount++;
        }
        if (extractedCount == 0) {
          throw HttpException('No files extracted from archive');
        }
      } catch (e) {
        // 清理可能部分解压的文件
        if (await modelDir.exists()) {
          await modelDir.delete(recursive: true);
        }
        if (e is HttpException) rethrow;
        throw HttpException('Tar extraction failed: $e');
      }
    } finally {
      // 无论成功失败，清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// 下载存档文件到系统临时目录（流式写入磁盘，避免 OOM）
  ///
  /// 支持断点续传：临时文件以 `model_{identifier}_download.part` 命名，
  /// 若文件已部分存在，自动以 HTTP Range 头续传（需服务器支持）。
  /// 网络错误时保留部分文件；URL 变更时从头开始。
  static Future<File> _downloadArchiveToTemp({
    required String archiveUrl,
    required String identifier,
    String? mirrorBaseUrl,
    int? archiveSizeBytes,
    OnDownloadProgress? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/model_${identifier}_download.part');

    // 检查是否有部分下载
    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    final candidates = <String>[];
    // 1. 自定义镜像
    final mirrorUrl = _resolveUrl(archiveUrl, mirrorBaseUrl);
    if (mirrorUrl != archiveUrl && !candidates.contains(mirrorUrl)) {
      candidates.add(mirrorUrl);
    }
    // 2. 原始 URL
    if (!candidates.contains(archiveUrl)) {
      candidates.add(archiveUrl);
    }
    // 3. 已知镜像（国内用户可用）
    for (final prefix in _mirrorPrefixes) {
      final ghfastUrl = '$prefix/$archiveUrl';
      if (!candidates.contains(ghfastUrl)) {
        candidates.add(ghfastUrl);
      }
    }

    HttpException? lastError;
    for (final url in candidates) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        final response = await http.Client().send(request);

        if (response.statusCode == 206) {
          // 服务器支持 Range，追加写入
          final sink = tempFile.openWrite(mode: FileMode.append);
          try {
            int received = existingBytes;
            await for (final chunk in response.stream) {
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call(received, archiveSizeBytes ?? received);
            }
          } finally {
            await sink.close();
          }
          return tempFile;
        } else if (response.statusCode == 200) {
          // 服务器不支持 Range 或文件有变化，从头下载
          if (existingBytes > 0) {
            await tempFile.delete();
            existingBytes = 0;
          }
          final sink = tempFile.openWrite();
          try {
            int received = 0;
            await for (final chunk in response.stream) {
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call(received, archiveSizeBytes ?? received);
            }
          } finally {
            await sink.close();
          }
          return tempFile;
        } else {
          lastError = HttpException(
            'HTTP ${response.statusCode} from $url',
          );
          continue;
        }
      } catch (e) {
        lastError = e is HttpException
            ? e
            : HttpException('$e');
        // 保留部分文件，下次重试可续传
        if (await tempFile.exists()) {
          existingBytes = await tempFile.length();
        } else {
          existingBytes = 0;
        }
      }
    }

    throw lastError ??
        HttpException('All download attempts failed');
  }

  static String _resolveUrl(String originalUrl, String? mirrorBaseUrl) {
    if (mirrorBaseUrl == null || mirrorBaseUrl.isEmpty) return originalUrl;

    final releasePrefix =
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/';
    if (originalUrl.startsWith(releasePrefix)) {
      final relativePath = originalUrl.substring(releasePrefix.length);
      return '${mirrorBaseUrl.replaceAll(RegExp(r'/$'), '')}/$relativePath';
    }
    return originalUrl;
  }
}