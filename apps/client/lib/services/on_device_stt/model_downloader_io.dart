import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../app_log_service.dart';
import '../route_resolver.dart';
import 'runtime_platform.dart' as runtime_platform;

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
    final archive =
        archiveSizeBytes ??
        (estimatedSizeMb != null
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
    files: const [ModelFile('model.int8.onnx'), ModelFile('tokens.txt')],
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
    files: const [ModelFile('model.int8.onnx'), ModelFile('tokens.txt')],
  );

  /// 所有已知模型配置列表（用于管理页、孤立目录检测等）
  static final all = <OnDeviceModelConfig>[
    senseVoice,
    whisperTiny,
    whisperBase,
    whisperSmall,
    whisperMedium,
    paraformer,
  ];

  /// 根据引擎名和 Whisper 模型大小返回对应的模型配置
  ///
  /// 这是整个项目中唯一的引擎→模型映射入口，所有消费方必须通过此方法获取配置。
  static OnDeviceModelConfig? forEngine(
    String engine, {
    String whisperSize = 'base',
  }) {
    return switch (engine) {
      'sense_voice' => senseVoice,
      'whisper' => switch (whisperSize) {
        'tiny' => whisperTiny,
        'small' => whisperSmall,
        'medium' => whisperMedium,
        _ => whisperBase,
      },
      'paraformer' => paraformer,
      _ => null,
    };
  }
}

/// 模型下载状态回调
typedef OnDownloadProgress = void Function(int received, int total);

typedef OnResourceDownloadProgress = void Function(DownloadProgress progress);

enum DownloadStopReason { paused, cancelled }

class ResourceDownloadStopped implements Exception {
  const ResourceDownloadStopped(this.reason);

  final DownloadStopReason reason;

  @override
  String toString() => 'Resource download ${reason.name}';
}

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.sourceLabel,
    required this.bytesPerSecond,
    this.extracting = false,
  });

  final int received;
  final int total;
  final String sourceLabel;
  final double bytesPerSecond;
  final bool extracting;

  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

class ResourceDownloadController {
  bool _paused = false;
  bool _cancelled = false;
  http.Client? _client;

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;

  void pause() {
    _paused = true;
    _client?.close();
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  void _bind(http.Client client) {
    if (_paused || _cancelled) {
      client.close();
      return;
    }
    _client = client;
  }

  void _unbind(http.Client client) {
    if (_client == client) {
      _client = null;
    }
  }
}

class RuntimeFile {
  const RuntimeFile(this.fileName);

  final String fileName;
}

class OnDeviceRuntimeConfig {
  const OnDeviceRuntimeConfig({
    required this.id,
    required this.displayName,
    required this.archiveUrl,
    required this.files,
    this.archiveSizeBytes,
    this.estimatedSizeMb,
  });

  final String id;
  final String displayName;
  final String archiveUrl;
  final List<RuntimeFile> files;
  final int? archiveSizeBytes;
  final int? estimatedSizeMb;
}

class KnownRuntimes {
  KnownRuntimes._();

  static const version = 'v1.13.2';
  static const _baseUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/$version';

  static OnDeviceRuntimeConfig? current() {
    if (Platform.isMacOS) {
      final arch = runtime_platform.currentSherpaOnnxRuntimeArch();
      return OnDeviceRuntimeConfig(
        id: 'sherpa-onnx-$version-osx-$arch',
        displayName: 'Sherpa ONNX Runtime $version macOS $arch',
        archiveUrl: '$_baseUrl/sherpa-onnx-native-lib-osx-$arch-$version.jar',
        estimatedSizeMb: arch == 'aarch64' ? 11 : 10,
        files: const [
          RuntimeFile('libsherpa-onnx-c-api.dylib'),
          RuntimeFile('libsherpa-onnx-cxx-api.dylib'),
          RuntimeFile('libonnxruntime.1.24.4.dylib'),
        ],
      );
    }
    if (Platform.isWindows) {
      return const OnDeviceRuntimeConfig(
        id: 'sherpa-onnx-v1.13.2-win-x64',
        displayName: 'Sherpa ONNX Runtime v1.13.2 Windows x64',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.2/sherpa-onnx-native-lib-win-x64-v1.13.2.jar',
        estimatedSizeMb: 8,
        files: [
          RuntimeFile('sherpa-onnx-c-api.dll'),
          RuntimeFile('sherpa-onnx-cxx-api.dll'),
          RuntimeFile('onnxruntime.dll'),
          RuntimeFile('onnxruntime_providers_shared.dll'),
        ],
      );
    }
    if (Platform.isLinux) {
      final arch = runtime_platform.currentSherpaOnnxRuntimeArch();
      return OnDeviceRuntimeConfig(
        id: 'sherpa-onnx-$version-linux-$arch',
        displayName: 'Sherpa ONNX Runtime $version Linux $arch',
        archiveUrl: '$_baseUrl/sherpa-onnx-native-lib-linux-$arch-$version.jar',
        estimatedSizeMb: arch == 'aarch64' ? 12 : 10,
        files: const [
          RuntimeFile('libsherpa-onnx-c-api.so'),
          RuntimeFile('libsherpa-onnx-cxx-api.so'),
          RuntimeFile('libonnxruntime.so'),
        ],
      );
    }
    if (Platform.isAndroid) {
      return const OnDeviceRuntimeConfig(
        id: 'sherpa-onnx-v1.13.2-android',
        displayName: 'Sherpa ONNX Runtime v1.13.2 Android',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.2/sherpa-onnx-v1.13.2-android.tar.bz2',
        estimatedSizeMb: 54,
        files: [
          RuntimeFile('libsherpa-onnx-c-api.so'),
          RuntimeFile('libsherpa-onnx-cxx-api.so'),
          RuntimeFile('libonnxruntime.so'),
        ],
      );
    }
    return null;
  }
}

/// 通用模型下载器
class ModelDownloader {
  ModelDownloader._();

  static final Set<String> _activeResourceDownloads = {};

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
    final dir = await getModelDirectory(modelId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> getRuntimeDir(String runtimeId) async {
    final dir = await getRuntimeDirectory(runtimeId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the canonical model directory without creating it.
  static Future<Directory> getModelDirectory(String modelId) async {
    final root = await getStorageDir();
    return Directory('${root.path}/$modelId');
  }

  /// Returns the canonical runtime directory without creating it.
  static Future<Directory> getRuntimeDirectory(String runtimeId) async {
    final root = await getStorageDir();
    return Directory('${root.path}/runtimes/$runtimeId');
  }

  /// 检查模型是否已下载完整
  static Future<bool> isModelReady(OnDeviceModelConfig config) async {
    final dir = await getModelDirectory(config.id);
    if (!await dir.exists()) return false;
    for (final file in config.files) {
      final f = File('${dir.path}/${file.relativePath}');
      if (!await f.exists()) return false;
      if (file.sizeBytes != null && await f.length() != file.sizeBytes) {
        return false;
      }
      // 即使没有已知 sizeBytes，0 字节文件必为损坏
      if (await f.length() == 0) return false;
    }
    return true;
  }

  static Future<bool> isRuntimeReady(OnDeviceRuntimeConfig config) async {
    final dir = await getRuntimeDirectory(config.id);
    if (!await dir.exists()) return false;
    if (Platform.isAndroid) {
      await _keepOnlyCurrentAndroidAbi(dir);
      if (!await _hasCurrentAndroidRuntimeAbi(dir)) return false;
    }
    final searchDir = await _runtimeSearchDir(dir);
    for (final file in config.files) {
      final found = await _findFile(searchDir, file.fileName);
      if (found == null) return false;
    }
    return true;
  }

  static Future<bool> isOnDeviceReady(OnDeviceModelConfig modelConfig) async {
    final runtimeConfig = KnownRuntimes.current();
    if (runtimeConfig == null) return false;
    return await isRuntimeReady(runtimeConfig) &&
        await isModelReady(modelConfig);
  }

  static Future<void> initSherpaOnnxBindings() async {
    final runtimeDir = await requireRuntimeLibraryDir();
    unawaited(
      AppLog.info(
        'Initializing sherpa-onnx runtime from $runtimeDir',
        source: 'on_device_stt',
      ),
    );

    // Android dlopen of an absolute-path library does not reliably resolve its
    // transitive dependencies from that same downloaded directory. Preload the
    // dependency chain in order, then let sherpa_onnx open the c-api library.
    try {
      if (Platform.isAndroid) {
        final onnxRuntime = File('$runtimeDir/libonnxruntime.so');
        final cxxApi = File('$runtimeDir/libsherpa-onnx-cxx-api.so');
        if (await onnxRuntime.exists()) {
          unawaited(
            AppLog.debug(
              'Preloading ${onnxRuntime.path}',
              source: 'on_device_stt',
            ),
          );
          DynamicLibrary.open(onnxRuntime.path);
        }
        if (await cxxApi.exists()) {
          unawaited(
            AppLog.debug('Preloading ${cxxApi.path}', source: 'on_device_stt'),
          );
          DynamicLibrary.open(cxxApi.path);
        }
      }

      initBindings(runtimeDir);
    } catch (e) {
      unawaited(
        AppLog.error(
          'Failed to load sherpa-onnx runtime from $runtimeDir',
          source: 'on_device_stt',
          error: e,
        ),
      );
      throw StateError(
        'Failed to load sherpa-onnx runtime from $runtimeDir: $e',
      );
    }
  }

  static Future<String?> getRuntimeLibraryDir(
    OnDeviceRuntimeConfig config,
  ) async {
    final dir = await getRuntimeDirectory(config.id);
    final firstFile = config.files.isEmpty ? null : config.files.first.fileName;
    if (firstFile == null) return null;
    if (Platform.isAndroid) {
      await _keepOnlyCurrentAndroidAbi(dir);
      if (!await _hasCurrentAndroidRuntimeAbi(dir)) return null;
    }
    final searchDir = await _runtimeSearchDir(dir);
    final first = await _findFile(searchDir, firstFile);
    return first?.parent.path;
  }

  static Future<int?> getRuntimeSize(String runtimeId) =>
      getResourceSize('runtimes/$runtimeId');

  /// 获取已下载模型的文件大小（字节），null 表示未下载
  static Future<int?> getModelSize(String modelId) async {
    return getResourceSize(modelId);
  }

  static Future<int?> getResourceSize(String resourcePath) async {
    final root = await getStorageDir();
    final dir = Directory('${root.path}/$resourcePath');
    // 递归统计所有文件大小
    int total = 0;
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total > 0 ? total : null;
  }

  /// 删除整个模型
  static Future<void> deleteModel(String modelId) async {
    final dir = await getModelDirectory(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _deleteTempFile(modelId);
  }

  static Future<void> deleteRuntime(String runtimeId) async {
    final dir = await getRuntimeDirectory(runtimeId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _deleteTempFile(runtimeId);
  }

  static Future<String> requireRuntimeLibraryDir() async {
    final runtimeConfig = KnownRuntimes.current();
    if (runtimeConfig == null) {
      throw StateError('No runtime config available for current platform');
    }
    if (!await isRuntimeReady(runtimeConfig)) {
      final dir = await getRuntimeDirectory(runtimeConfig.id);
      throw StateError('Runtime not ready: ${runtimeConfig.id} at ${dir.path}');
    }
    final runtimeDir = await getRuntimeLibraryDir(runtimeConfig);
    if (runtimeDir == null) {
      final dir = await getRuntimeDirectory(runtimeConfig.id);
      throw StateError('Runtime library not found in ${dir.path}');
    }
    return runtimeDir;
  }

  /// GitHub 代理镜像 URL 列表（按优先级排序）
  ///
  /// ghfast.top 在国内可直接访问 GitHub release 资源。
  /// 如果 ghfast.top 失效，可在此追加新的镜像地址。
  static const _mirrorPrefixes = ['https://ghfast.top'];

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
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onDetailedProgress,
  }) async {
    final lockId = 'model:${config.id}';
    if (!_activeResourceDownloads.add(lockId)) {
      throw StateError('Resource download already running: ${config.id}');
    }
    try {
      await _downloadModelLocked(
        config: config,
        onProgress: onProgress,
        mirrorBaseUrl: mirrorBaseUrl,
        downloadSourceMode: downloadSourceMode,
        controller: controller,
        onDetailedProgress: onDetailedProgress,
      );
    } finally {
      _activeResourceDownloads.remove(lockId);
    }
  }

  static Future<void> _downloadModelLocked({
    required OnDeviceModelConfig config,
    OnDownloadProgress? onProgress,
    String? mirrorBaseUrl,
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onDetailedProgress,
  }) async {
    final modelDir = await getModelDir(config.id);

    // 清理已有文件（修复旧版本提取到子目录的损坏状态）
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    await modelDir.create(recursive: true);

    // 跟踪下载阶段的最终进度值（提取阶段复用，避免进度条回退）
    int downloadTotal = config.archiveSizeBytes ?? 0;
    String downloadSource = '';

    // 1. 下载 .tar.bz2 存档到临时文件
    final tempFile = await _downloadArchiveToTemp(
      archiveUrl: config.archiveUrl,
      identifier: config.id,
      mirrorBaseUrl: mirrorBaseUrl,
      downloadSourceMode: downloadSourceMode,
      archiveSizeBytes: config.archiveSizeBytes,
      controller: controller,
      onProgress: (progress) {
        downloadTotal = progress.total;
        downloadSource = progress.sourceLabel;
        onProgress?.call(progress.received, progress.total);
        onDetailedProgress?.call(progress);
      },
    );

    try {
      // 2. 切换到提取阶段，保持最近一次下载进度值（进度条不归零）
      onProgress?.call(downloadTotal, downloadTotal);
      onDetailedProgress?.call(
        DownloadProgress(
          received: downloadTotal,
          total: downloadTotal,
          sourceLabel: downloadSource,
          bytesPerSecond: 0,
          extracting: true,
        ),
      );

      try {
        await _extractModelTarBz2Archive(tempFile, modelDir, config.id);
        if (!await isModelReady(config)) {
          throw HttpException('Model files missing after extraction');
        }

        // 提取完成 → 报告 100%
        onProgress?.call(downloadTotal, downloadTotal);
        onDetailedProgress?.call(
          DownloadProgress(
            received: downloadTotal,
            total: downloadTotal,
            sourceLabel: downloadSource,
            bytesPerSecond: 0,
          ),
        );
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

  static Future<void> downloadRuntime({
    required OnDeviceRuntimeConfig config,
    String? mirrorBaseUrl,
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onProgress,
  }) async {
    final lockId = 'runtime:${config.id}';
    if (!_activeResourceDownloads.add(lockId)) {
      throw StateError('Resource download already running: ${config.id}');
    }
    try {
      await _downloadRuntimeLocked(
        config: config,
        mirrorBaseUrl: mirrorBaseUrl,
        downloadSourceMode: downloadSourceMode,
        controller: controller,
        onProgress: onProgress,
      );
    } finally {
      _activeResourceDownloads.remove(lockId);
    }
  }

  static Future<void> _downloadRuntimeLocked({
    required OnDeviceRuntimeConfig config,
    String? mirrorBaseUrl,
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onProgress,
  }) async {
    final runtimeDir = await getRuntimeDir(config.id);
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    await runtimeDir.create(recursive: true);

    // 跟踪下载阶段最终进度（提取阶段复用）
    int downloadTotal = config.archiveSizeBytes ?? 0;
    String downloadSource = '';

    final tempFile = await _downloadArchiveToTemp(
      archiveUrl: config.archiveUrl,
      identifier: config.id,
      mirrorBaseUrl: mirrorBaseUrl,
      downloadSourceMode: downloadSourceMode,
      archiveSizeBytes: config.archiveSizeBytes,
      controller: controller,
      onProgress: (progress) {
        downloadTotal = progress.total;
        downloadSource = progress.sourceLabel;
        onProgress?.call(progress);
      },
    );

    try {
      onProgress?.call(
        DownloadProgress(
          received: downloadTotal,
          total: downloadTotal,
          sourceLabel: downloadSource,
          bytesPerSecond: 0,
          extracting: true,
        ),
      );
      await _extractArchive(tempFile, runtimeDir);

      // Android 归档包含多 ABI .so 文件（arm64-v8a/ 等），
      // 清理其他 ABI 只保留当前设备的，避免 _findFile 找到错误架构。
      if (Platform.isAndroid) {
        await _keepOnlyCurrentAndroidAbi(runtimeDir);
        if (!await _hasCurrentAndroidRuntimeAbi(runtimeDir)) {
          throw HttpException('Runtime ABI does not match current process');
        }
      }

      for (final file in config.files) {
        final searchDir = await _runtimeSearchDir(runtimeDir);
        final found = await _findFile(searchDir, file.fileName);
        if (found == null) {
          throw HttpException('Runtime file missing: ${file.fileName}');
        }
      }
      // 提取完成 → 报告 100%
      onProgress?.call(
        DownloadProgress(
          received: downloadTotal,
          total: downloadTotal,
          sourceLabel: downloadSource,
          bytesPerSecond: 0,
        ),
      );
    } catch (e) {
      if (await runtimeDir.exists()) {
        await runtimeDir.delete(recursive: true);
      }
      rethrow;
    } finally {
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
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
    int? archiveSizeBytes,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onProgress,
    bool allowRangeReset = true,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/model_${identifier}_download.part');
    final tempMetaFile = File(
      '${tempDir.path}/model_${identifier}_download.url',
    );

    // 检查是否有部分下载
    int existingBytes = 0;
    if (await tempFile.exists()) {
      final previousArchiveUrl = await tempMetaFile.exists()
          ? (await tempMetaFile.readAsString()).trim()
          : '';
      if (previousArchiveUrl.isNotEmpty && previousArchiveUrl != archiveUrl) {
        await tempFile.delete();
        existingBytes = 0;
      }
    }
    await tempMetaFile.writeAsString(archiveUrl);

    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
      if (archiveSizeBytes != null && existingBytes >= archiveSizeBytes) {
        await tempFile.delete();
        existingBytes = 0;
      }
    }

    var candidates = _buildDownloadCandidates(
      archiveUrl,
      mirrorBaseUrl,
      downloadSourceMode,
    );
    if (downloadSourceMode == DownloadSourceMode.auto) {
      candidates = await _orderCandidatesByProbeLatency(candidates);
    }

    HttpException? lastError;
    for (final url in candidates) {
      if (controller?.isPaused ?? false) {
        throw const ResourceDownloadStopped(DownloadStopReason.paused);
      }
      if (controller?.isCancelled ?? false) {
        await _deleteTempFile(identifier);
        throw const ResourceDownloadStopped(DownloadStopReason.cancelled);
      }
      final sourceLabel = _sourceLabelFromUrl(url, mirrorBaseUrl);
      final stopwatch = Stopwatch()..start();
      int speedBaseBytes = existingBytes;
      var speedBaseElapsed = Duration.zero;
      http.Client? client;
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        client = http.Client();
        controller?._bind(client);
        final response = await client.send(request);

        if (response.statusCode == 206) {
          // 服务器支持 Range，追加写入
          final sink = tempFile.openWrite(mode: FileMode.append);
          try {
            int received = existingBytes;
            final total =
                archiveSizeBytes ??
                (response.contentLength != null
                    ? existingBytes + response.contentLength!
                    : received);
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 30),
            )) {
              _throwIfStopped(controller, identifier);
              sink.add(chunk);
              received += chunk.length;
              final speed = _speedBytesPerSecond(
                stopwatch,
                received,
                speedBaseBytes,
                speedBaseElapsed,
              );
              if (stopwatch.elapsed - speedBaseElapsed >
                  const Duration(seconds: 1)) {
                speedBaseBytes = received;
                speedBaseElapsed = stopwatch.elapsed;
              }
              onProgress?.call(
                DownloadProgress(
                  received: received,
                  total: total,
                  sourceLabel: sourceLabel,
                  bytesPerSecond: speed,
                ),
              );
            }
          } finally {
            await sink.close();
            controller?._unbind(client);
            client.close();
            client = null;
          }
          return tempFile;
        } else if (response.statusCode == 416 &&
            existingBytes > 0 &&
            allowRangeReset) {
          // 本地断点超出远端文件范围，通常是旧 .part 文件或源切换造成。
          // 删除分片后重新从当前候选列表无 Range 下载，避免用户看到 416。
          controller?._unbind(client);
          client.close();
          client = null;
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          return _downloadArchiveToTemp(
            archiveUrl: archiveUrl,
            identifier: identifier,
            mirrorBaseUrl: mirrorBaseUrl,
            downloadSourceMode: downloadSourceMode,
            archiveSizeBytes: archiveSizeBytes,
            controller: controller,
            onProgress: onProgress,
            allowRangeReset: false,
          );
        } else if (response.statusCode == 200) {
          // 服务器不支持 Range 或文件有变化，从头下载
          if (existingBytes > 0) {
            await tempFile.delete();
            existingBytes = 0;
          }
          speedBaseBytes = 0;
          speedBaseElapsed = Duration.zero;
          final sink = tempFile.openWrite();
          try {
            int received = 0;
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 30),
            )) {
              _throwIfStopped(controller, identifier);
              sink.add(chunk);
              received += chunk.length;
              final speed = _speedBytesPerSecond(
                stopwatch,
                received,
                speedBaseBytes,
                speedBaseElapsed,
              );
              if (stopwatch.elapsed - speedBaseElapsed >
                  const Duration(seconds: 1)) {
                speedBaseBytes = received;
                speedBaseElapsed = stopwatch.elapsed;
              }
              onProgress?.call(
                DownloadProgress(
                  received: received,
                  total: archiveSizeBytes ?? response.contentLength ?? received,
                  sourceLabel: sourceLabel,
                  bytesPerSecond: speed,
                ),
              );
            }
          } finally {
            await sink.close();
            controller?._unbind(client);
            client.close();
            client = null;
          }
          return tempFile;
        } else {
          lastError = HttpException('HTTP ${response.statusCode} from $url');
          controller?._unbind(client);
          client.close();
          client = null;
          continue;
        }
      } on ResourceDownloadStopped {
        if (client != null) {
          controller?._unbind(client);
          client.close();
        }
        rethrow;
      } catch (e) {
        if (client != null) {
          controller?._unbind(client);
          client.close();
        }
        lastError = e is HttpException ? e : HttpException('$e');
        // 保留部分文件，下次重试可续传
        if (await tempFile.exists()) {
          existingBytes = await tempFile.length();
        } else {
          existingBytes = 0;
        }
      }
    }

    throw lastError ?? HttpException('All download attempts failed');
  }

  static List<String> _buildDownloadCandidates(
    String archiveUrl,
    String? mirrorBaseUrl,
    DownloadSourceMode mode,
  ) {
    final mirrorUrl = _resolveUrl(archiveUrl, mirrorBaseUrl);
    final customMirror = mirrorUrl != archiveUrl ? mirrorUrl : null;
    final defaultMirror = '$defaultMirrorPrefix/$archiveUrl';
    final urls = <String>[];
    void add(String? url) {
      if (url != null && url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }

    if (mode == DownloadSourceMode.githubOnly) {
      add(archiveUrl);
    } else if (mode == DownloadSourceMode.mirrorFirst) {
      add(customMirror);
      add(archiveUrl);
      add(defaultMirror);
    } else {
      add(archiveUrl);
      add(customMirror);
      add(defaultMirror);
    }
    for (final prefix in _mirrorPrefixes) {
      add('$prefix/$archiveUrl');
    }
    return urls;
  }

  static Future<List<String>> _orderCandidatesByProbeLatency(
    List<String> urls,
  ) async {
    if (urls.length <= 1) return urls;
    final probes = await Future.wait(urls.map(_probeDownloadCandidate));
    final byUrl = {for (final probe in probes) probe.url: probe};
    final ordered = [...urls]
      ..sort((a, b) {
        final pa = byUrl[a]!;
        final pb = byUrl[b]!;
        if (pa.reachable != pb.reachable) return pa.reachable ? -1 : 1;
        if (!pa.reachable && !pb.reachable) {
          return urls.indexOf(a).compareTo(urls.indexOf(b));
        }
        return pa.elapsed.compareTo(pb.elapsed);
      });
    return ordered;
  }

  static Future<_DownloadCandidateProbe> _probeDownloadCandidate(
    String url,
  ) async {
    final client = http.Client();
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('HEAD', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 6));
      stopwatch.stop();
      return _DownloadCandidateProbe(
        url: url,
        reachable: response.statusCode >= 200 && response.statusCode < 400,
        elapsed: stopwatch.elapsed,
      );
    } catch (_) {
      stopwatch.stop();
      return _DownloadCandidateProbe(
        url: url,
        reachable: false,
        elapsed: const Duration(days: 1),
      );
    } finally {
      client.close();
    }
  }

  static String _resolveUrl(String originalUrl, String? mirrorBaseUrl) {
    if (mirrorBaseUrl == null || mirrorBaseUrl.isEmpty) return originalUrl;

    final releasePrefix =
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/';
    if (originalUrl.startsWith(releasePrefix)) {
      final relativePath = originalUrl.substring(releasePrefix.length);
      return '${mirrorBaseUrl.replaceAll(RegExp(r'/$'), '')}/$relativePath';
    }
    return '${mirrorBaseUrl.replaceAll(RegExp(r'/+$'), '')}/$originalUrl';
  }

  static const defaultMirrorPrefix = 'https://ghfast.top';

  static String _sourceLabelFromUrl(String url, String? mirrorBaseUrl) {
    if (mirrorBaseUrl != null && mirrorBaseUrl.isNotEmpty) {
      final prefix = mirrorBaseUrl.replaceAll(RegExp(r'/+$'), '');
      if (url.startsWith(prefix)) {
        return Uri.tryParse(prefix)?.host ?? prefix;
      }
    }
    if (url.startsWith(defaultMirrorPrefix)) return 'ghfast.top';
    if (url.contains('github.com')) return 'GitHub';
    return Uri.tryParse(url)?.host ?? url;
  }

  static double _speedBytesPerSecond(
    Stopwatch stopwatch,
    int received,
    int baseBytes,
    Duration baseElapsed,
  ) {
    final elapsed = stopwatch.elapsed - baseElapsed;
    if (elapsed.inMilliseconds <= 0) return 0;
    return (received - baseBytes) * 1000 / elapsed.inMilliseconds;
  }

  static void _throwIfStopped(
    ResourceDownloadController? controller,
    String identifier,
  ) {
    if (controller?.isPaused ?? false) {
      throw const ResourceDownloadStopped(DownloadStopReason.paused);
    }
    if (controller?.isCancelled ?? false) {
      unawaited(_deleteTempFile(identifier));
      throw const ResourceDownloadStopped(DownloadStopReason.cancelled);
    }
  }

  static Future<void> _deleteTempFile(String identifier) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/model_${identifier}_download.part');
    final tempMetaFile = File(
      '${tempDir.path}/model_${identifier}_download.url',
    );
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    if (await tempMetaFile.exists()) {
      await tempMetaFile.delete();
    }
  }

  static Future<void> _extractModelTarBz2Archive(
    File archiveFile,
    Directory modelDir,
    String identifier,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final tarFile = File('${tempDir.path}/model_${identifier}_extract.tar');
    InputFileStream? input;
    OutputFileStream? output;
    InputFileStream? tarInput;
    try {
      input = InputFileStream(archiveFile.path);
      output = OutputFileStream(tarFile.path);
      BZip2Decoder().decodeBuffer(input, output: output);
      input.closeSync();
      output.closeSync();
      input = null;
      output = null;

      tarInput = InputFileStream(tarFile.path);
      final archive = TarDecoder().decodeBuffer(tarInput);
      final fileEntries = archive.where((entry) => entry.isFile).toList();
      if (fileEntries.isEmpty) {
        throw HttpException('Archive is empty or contains no files');
      }

      final commonTopPrefix = _commonTopLevelPrefix(fileEntries);
      var extractedCount = 0;
      for (final entry in fileEntries) {
        final relativeName =
            (commonTopPrefix != null &&
                entry.name.startsWith('$commonTopPrefix/'))
            ? entry.name.substring(commonTopPrefix.length + 1)
            : entry.name;
        if (relativeName.isEmpty || relativeName.contains('..')) continue;

        final destPath = '${modelDir.path}/$relativeName';
        final destDir = Directory(
          destPath.substring(0, destPath.lastIndexOf('/')),
        );
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        final fileOutput = OutputFileStream(destPath);
        try {
          entry.writeContent(fileOutput);
        } finally {
          fileOutput.closeSync();
        }
        extractedCount++;
      }
      if (extractedCount == 0) {
        throw HttpException('No files extracted from archive');
      }
    } catch (e) {
      if (e is HttpException) rethrow;
      throw HttpException('Model archive extraction failed: $e');
    } finally {
      input?.closeSync();
      output?.closeSync();
      tarInput?.closeSync();
      if (await tarFile.exists()) {
        await tarFile.delete();
      }
    }
  }

  static String? _commonTopLevelPrefix(List<ArchiveFile> fileEntries) {
    String? commonTopPrefix;
    for (final entry in fileEntries) {
      final slashPos = entry.name.indexOf('/');
      if (slashPos == -1) return null;
      final prefix = entry.name.substring(0, slashPos);
      if (commonTopPrefix == null) {
        commonTopPrefix = prefix;
      } else if (commonTopPrefix != prefix) {
        return null;
      }
    }
    return commonTopPrefix;
  }

  /// 返回运行时库文件应搜索的目录。
  ///
  /// Android 运行时统一规范化到 `<runtime>/<abi>/`，加载动态库时只
  /// 使用当前设备 ABI 目录，避免递归搜索命中其他架构的 `.so`。
  static Future<Directory> _runtimeSearchDir(Directory runtimeDir) async {
    if (!Platform.isAndroid) return runtimeDir;
    final abi = await _selectCurrentAndroidAbi(runtimeDir);
    if (abi == null) return runtimeDir;
    final abiDir = Directory('${runtimeDir.path}/$abi');
    if (await abiDir.exists()) return abiDir;
    return runtimeDir;
  }

  /// Android 归档提取后，只保留当前设备 ABI 的 .so 文件。
  ///
  /// sherpa-onnx Android 包可能是 `jniLibs/<abi>/`、`<abi>/`，也可能
  /// 外面还有一层版本目录。这里先在整个运行时目录中定位当前 ABI 目录，
  /// 再统一移动到 `<runtime>/<abi>/`，最后删除其他 ABI 与残留顶层目录。
  static Future<void> _keepOnlyCurrentAndroidAbi(Directory runtimeDir) async {
    if (!Platform.isAndroid) return;
    final abi = await _selectCurrentAndroidAbi(runtimeDir);
    if (abi == null) {
      unawaited(
        AppLog.warning(
          'Android sherpa-onnx runtime ABI does not match current process',
          source: 'on_device_stt',
        ),
      );
      return;
    }
    final canonicalAbiDir = Directory('${runtimeDir.path}/$abi');
    final sourceAbiDir = await _findAndroidAbiDir(runtimeDir, abi);

    if (sourceAbiDir != null) {
      if (!await canonicalAbiDir.exists()) {
        await canonicalAbiDir.create(recursive: true);
      }
      if (sourceAbiDir.path != canonicalAbiDir.path) {
        await _moveDirectoryContents(sourceAbiDir, canonicalAbiDir);
      }
    } else {
      await _moveRootAndroidLibraries(runtimeDir, canonicalAbiDir);
    }

    await _deleteAndroidRuntimeResidue(runtimeDir, canonicalAbiDir, abi);
  }

  static Future<bool> _hasCurrentAndroidRuntimeAbi(Directory runtimeDir) async {
    final abi = await _selectCurrentAndroidAbi(runtimeDir);
    if (abi == null) return false;
    final abiDir = Directory('${runtimeDir.path}/$abi');
    if (!await abiDir.exists()) return false;
    final runtimeInfo = await runtime_platform.currentAndroidRuntimeInfo();
    if (runtimeInfo == null) return true;
    final lib = await _findFile(abiDir, 'libonnxruntime.so');
    if (lib == null) return true;
    final elfClass = await _readElfClass(lib);
    if (elfClass == null) return true;
    return elfClass == (runtimeInfo.is64Bit ? _elfClass64 : _elfClass32);
  }

  static Future<String?> _selectCurrentAndroidAbi(Directory runtimeDir) async {
    final abiDirs = await _findAndroidAbiDirs(runtimeDir);
    final availableAbis = abiDirs.keys.toSet();
    final runtimeInfo = await runtime_platform.currentAndroidRuntimeInfo();

    if (runtimeInfo != null && availableAbis.isNotEmpty) {
      final processAbis = runtimeInfo.is64Bit
          ? runtimeInfo.supported64BitAbis
          : runtimeInfo.supported32BitAbis;
      for (final abi in processAbis) {
        if (availableAbis.contains(abi)) return abi;
      }
      for (final abi in runtimeInfo.supportedAbis) {
        if (availableAbis.contains(abi) &&
            _isAbi64Bit(abi) == runtimeInfo.is64Bit) {
          return abi;
        }
      }
      final elfMatch = await _findAndroidAbiByElfClass(
        abiDirs,
        runtimeInfo.is64Bit,
      );
      if (elfMatch != null) return elfMatch;
      return null;
    }

    final currentAbi = runtime_platform.currentSherpaOnnxRuntimeArch();
    if (availableAbis.contains(currentAbi)) return currentAbi;

    final currentIs64Bit = _isAbi64Bit(currentAbi);
    final elfMatch = await _findAndroidAbiByElfClass(abiDirs, currentIs64Bit);
    if (elfMatch != null) return elfMatch;

    return currentAbi;
  }

  static bool _isAbi64Bit(String abi) {
    return abi == 'arm64-v8a' || abi == 'x86_64';
  }

  static Future<String?> _findAndroidAbiByElfClass(
    Map<String, Directory> abiDirs,
    bool is64Bit,
  ) async {
    for (final abi in _androidAbiPreferenceOrder) {
      final dir = abiDirs[abi];
      if (dir == null) continue;
      final lib = await _findFile(dir, 'libonnxruntime.so');
      if (lib == null) continue;
      final elfClass = await _readElfClass(lib);
      if (elfClass == null) continue;
      if (elfClass == (is64Bit ? _elfClass64 : _elfClass32)) {
        return abi;
      }
    }
    return null;
  }

  static const _elfClass32 = 1;
  static const _elfClass64 = 2;
  static const _androidAbiPreferenceOrder = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  static Future<int?> _readElfClass(File file) async {
    try {
      final stream = file.openRead(0, 5);
      final chunks = await stream.toList();
      if (chunks.isEmpty) return null;
      final header = chunks.expand((chunk) => chunk).toList();
      if (header.length < 5) return null;
      if (header[0] != 0x7f ||
          header[1] != 0x45 ||
          header[2] != 0x4c ||
          header[3] != 0x46) {
        return null;
      }
      return header[4];
    } catch (_) {
      return null;
    }
  }

  static bool _isKnownAndroidAbi(String name) {
    return name == 'arm64-v8a' ||
        name == 'armeabi-v7a' ||
        name == 'x86_64' ||
        name == 'x86';
  }

  static Future<void> _moveDirectoryContents(
    Directory src,
    Directory dst,
  ) async {
    await for (final entity in src.list()) {
      if (entity is File) {
        await entity.rename('${dst.path}/${_entityName(entity)}');
      } else if (entity is Directory) {
        final subDst = Directory('${dst.path}/${_entityName(entity)}');
        if (!await subDst.exists()) {
          await subDst.create(recursive: true);
        }
        await _moveDirectoryContents(entity, subDst);
      }
    }
  }

  static Future<void> _moveRootAndroidLibraries(
    Directory runtimeDir,
    Directory canonicalAbiDir,
  ) async {
    if (!await runtimeDir.exists()) return;
    await for (final entity in runtimeDir.list()) {
      if (entity is! File) continue;
      final name = _entityName(entity);
      if (!name.endsWith('.so')) continue;
      if (!await canonicalAbiDir.exists()) {
        await canonicalAbiDir.create(recursive: true);
      }
      await entity.rename('${canonicalAbiDir.path}/$name');
    }
  }

  static Future<Directory?> _findAndroidAbiDir(
    Directory runtimeDir,
    String abi,
  ) async {
    if (!await runtimeDir.exists()) return null;
    Directory? fallback;
    await for (final entity in runtimeDir.list(recursive: true)) {
      if (entity is! Directory) continue;
      final name = _entityName(entity);
      if (name != abi) continue;
      if (_entityName(entity.parent) == 'jniLibs') {
        return entity;
      }
      fallback ??= entity;
    }
    return fallback;
  }

  static Future<Map<String, Directory>> _findAndroidAbiDirs(
    Directory runtimeDir,
  ) async {
    final result = <String, Directory>{};
    if (!await runtimeDir.exists()) return result;
    await for (final entity in runtimeDir.list(recursive: true)) {
      if (entity is! Directory) continue;
      final name = _entityName(entity);
      if (!_isKnownAndroidAbi(name)) continue;
      final existing = result[name];
      if (existing == null || _entityName(entity.parent) == 'jniLibs') {
        result[name] = entity;
      }
    }
    return result;
  }

  static Future<void> _deleteAndroidRuntimeResidue(
    Directory runtimeDir,
    Directory canonicalAbiDir,
    String abi,
  ) async {
    if (!await runtimeDir.exists()) return;
    await for (final entity in runtimeDir.list()) {
      final name = _entityName(entity);
      if (entity is File) {
        if (name.endsWith('.so')) {
          await entity.delete();
        }
        continue;
      }
      if (entity is! Directory) continue;
      if (entity.path == canonicalAbiDir.path) continue;
      if (name == 'jniLibs' || _isKnownAndroidAbi(name)) {
        await entity.delete(recursive: true);
        continue;
      }
      final containsCurrentAbi = await _containsAndroidAbiDir(entity, abi);
      final containsAnyAbi =
          containsCurrentAbi || await _containsAnyAndroidAbiDir(entity);
      if (containsAnyAbi) {
        await entity.delete(recursive: true);
      }
    }
  }

  static Future<bool> _containsAndroidAbiDir(Directory dir, String abi) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is Directory && _entityName(entity) == abi) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _containsAnyAndroidAbiDir(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is Directory && _isKnownAndroidAbi(_entityName(entity))) {
        return true;
      }
    }
    return false;
  }

  static Future<File?> _findFile(Directory dir, String fileName) async {
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && _entityName(entity) == fileName) {
        return entity;
      }
    }
    return null;
  }

  static String _entityName(FileSystemEntity entity) {
    return entity.path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .last;
  }

  static Future<void> _extractArchive(
    File archiveFile,
    Directory targetDir,
  ) async {
    final bytes = await archiveFile.readAsBytes();
    List<int> archiveBytes = bytes;
    if (archiveFile.path.endsWith('.bz2') || _looksLikeBzip2(bytes)) {
      archiveBytes = BZip2Decoder().decodeBytes(bytes);
    }
    final archive = archiveFile.path.endsWith('.jar') || _looksLikeZip(bytes)
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(archiveBytes);
    for (final entry in archive.where((e) => e.isFile)) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.contains('..')) continue;
      final destPath = '${targetDir.path}/$name';
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
    }
  }

  static bool _looksLikeBzip2(List<int> bytes) =>
      bytes.length > 2 && bytes[0] == 0x42 && bytes[1] == 0x5a;

  static bool _looksLikeZip(List<int> bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
}

class _DownloadCandidateProbe {
  const _DownloadCandidateProbe({
    required this.url,
    required this.reachable,
    required this.elapsed,
  });

  final String url;
  final bool reachable;
  final Duration elapsed;
}
