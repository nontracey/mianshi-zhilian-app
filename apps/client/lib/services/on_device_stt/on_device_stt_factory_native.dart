import 'package:flutter/foundation.dart';

import 'engine_paraformer.dart';
import 'engine_sensevoice.dart';
import 'engine_whisper.dart';
import 'on_device_stt_service.dart';

/// 创建本机 STT 服务实例
/// [engine] — 'sense_voice', 'whisper', 'paraformer'
/// [modelDir] — 模型文件所在目录路径
/// [whisperModelSize] — 仅 whisper 引擎：'tiny'/'base'/'small'/'medium'
OnDeviceSttService createOnDeviceSttService({
  required String engine,
  required String modelDir,
  String whisperModelSize = 'base',
}) {
  if (kIsWeb) {
    throw UnsupportedError('On-device STT is not supported on web');
  }
  return switch (engine) {
    'sense_voice' => SenseVoiceEngine(modelDir: modelDir),
    'whisper' => WhisperOnnxEngine(
      modelDir: modelDir,
      modelSize: whisperModelSize,
    ),
    'paraformer' => ParaformerEngine(modelDir: modelDir),
    _ => SenseVoiceEngine(modelDir: modelDir),
  };
}