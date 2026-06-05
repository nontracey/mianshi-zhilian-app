import '../route_resolver.dart';

class ModelFile {
  const ModelFile(this.relativePath, [this.sizeBytes]);

  final String relativePath;
  final int? sizeBytes;
}

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

  int get requiredDiskBytes {
    final archive =
        archiveSizeBytes ??
        (estimatedSizeMb != null
            ? estimatedSizeMb! * 1024 * 1024
            : 100 * 1024 * 1024);
    return archive * 3;
  }
}

class KnownModels {
  KnownModels._();

  static final senseVoice = OnDeviceModelConfig(
    id: 'sense-voice',
    displayName: 'SenseVoice 小型多语言',
    estimatedSizeMb: 155,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
    archiveSizeBytes: 163002883,
    files: const [ModelFile('model.int8.onnx'), ModelFile('tokens.txt')],
  );

  static final whisperBase = OnDeviceModelConfig(
    id: 'whisper-base',
    displayName: 'Whisper Base',
    estimatedSizeMb: 198,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
    archiveSizeBytes: 207557382,
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
    archiveSizeBytes: 116204861,
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
    archiveSizeBytes: 639387718,
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
    archiveSizeBytes: 1931372882,
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
    archiveSizeBytes: 77920048,
    files: const [ModelFile('model.int8.onnx'), ModelFile('tokens.txt')],
  );

  static final all = <OnDeviceModelConfig>[
    senseVoice,
    whisperTiny,
    whisperBase,
    whisperSmall,
    whisperMedium,
    paraformer,
  ];

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

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;

  void pause() => _paused = true;
  void cancel() => _cancelled = true;
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

  static OnDeviceRuntimeConfig? current() => null;
}

class ModelStoragePath {
  const ModelStoragePath(this.path);

  final String path;

  Future<bool> exists() async => false;
}

class ModelDownloader {
  ModelDownloader._();

  static Future<ModelStoragePath> getStorageDir() async {
    return const ModelStoragePath('');
  }

  static Future<ModelStoragePath> getModelDirectory(String modelId) async {
    return ModelStoragePath('web/on_device_models/$modelId');
  }

  static Future<ModelStoragePath> getRuntimeDirectory(String runtimeId) async {
    return ModelStoragePath('web/on_device_runtimes/$runtimeId');
  }

  static Future<ModelStoragePath> getModelDir(String modelId) async {
    return getModelDirectory(modelId);
  }

  static Future<bool> isModelReady(OnDeviceModelConfig config) async => false;

  static Future<bool> isRuntimeReady(OnDeviceRuntimeConfig config) async =>
      false;

  static Future<bool> isOnDeviceReady(OnDeviceModelConfig modelConfig) async =>
      false;

  static Future<int> getModelSize(String modelId) async => 0;

  static Future<int> getRuntimeSize(String runtimeId) async => 0;

  static Future<void> initSherpaOnnxBindings() async {
    throw UnsupportedError('On-device STT is not supported on web');
  }

  static Future<String> requireRuntimeLibraryDir() async {
    throw UnsupportedError('On-device STT is not supported on web');
  }

  static Future<void> deleteModel(String modelId) async {}

  static Future<void> deleteRuntime(String runtimeId) async {}

  static Future<void> downloadModel({
    required OnDeviceModelConfig config,
    OnDownloadProgress? onProgress,
    String? mirrorBaseUrl,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onDetailedProgress,
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
  }) async {
    throw UnsupportedError('On-device STT is not supported on web');
  }

  static Future<void> downloadRuntime({
    required OnDeviceRuntimeConfig config,
    String? mirrorBaseUrl,
    ResourceDownloadController? controller,
    OnResourceDownloadProgress? onProgress,
    DownloadSourceMode downloadSourceMode = DownloadSourceMode.auto,
  }) async {
    throw UnsupportedError('On-device STT is not supported on web');
  }
}
