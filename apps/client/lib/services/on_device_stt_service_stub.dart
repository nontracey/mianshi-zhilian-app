/// Web stub for [OnDeviceSttService].
///
/// whisper_kit is not available on web. This stub ensures compilation
/// succeeds; all calls are no-ops or throw [UnsupportedError].
class OnDeviceSttService {
  bool get isModelReady => false;
  bool get isModelDownloading => false;
  String get modelStatus => 'not_downloaded';
  bool get isRunning => false;

  Future<void> deleteModel() async {}

  Future<void> initModel({void Function(int received, int total)? onProgress}) async {
    throw UnsupportedError('OnDeviceSttService is not available on web');
  }

  Future<void> startStreaming({
    required void Function(String accumulatedText) onResult,
    void Function(String status)? onStatus,
  }) async {
    throw UnsupportedError('OnDeviceSttService is not available on web');
  }

  Future<void> stopStreaming() async {}

  void dispose() {}
}