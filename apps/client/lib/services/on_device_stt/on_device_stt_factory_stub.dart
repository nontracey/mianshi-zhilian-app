import 'on_device_stt_service.dart';

/// 创建本机 STT 服务实例（Web 桩，总是抛出 UnsupportedError）
OnDeviceSttService createOnDeviceSttService({
  required String engine,
  required String modelDir,
  String whisperModelSize = 'base',
}) {
  return OnDeviceSttStub();
}