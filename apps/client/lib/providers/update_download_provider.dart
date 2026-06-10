import 'package:flutter/foundation.dart';

import '../services/app_version_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';

enum InstallerStatus { idle, downloading, readyToInstall, failed }

/// 全局更新下载控制器：把"下载安装包"的生命周期从单个页面/对话框中抽离，
/// 使其在应用内切换页面时不中断，并把"已校验安装包"的路径持久化，
/// 让用户即便没有第一时间安装、之后也能从更新页再次打开安装。
///
/// 注意：这是"应用内常驻"，不是 OS 级后台下载（App 被系统挂起仍会停）。
/// 安装包路径是设备本地信息，故记录键不进同步白名单。
class UpdateDownloadProvider extends ChangeNotifier {
  UpdateDownloadProvider(this._storage);

  final StorageService _storage;

  static const _recordKey = 'downloaded_installer';

  InstallerStatus _status = InstallerStatus.idle;
  InstallerStatus get status => _status;
  bool get isDownloading => _status == InstallerStatus.downloading;

  int _received = 0;
  int _total = 0;
  String _source = '';
  int get received => _received;
  int get total => _total;
  String get source => _source;

  String? _version;
  String? _filePath;

  /// 当前已就绪可安装的版本（无则 null）。
  String? get readyVersion =>
      _status == InstallerStatus.readyToInstall ? _version : null;
  String? get filePath => _filePath;

  /// 正在下载或已就绪的版本号（用于进度展示），无则空串。
  String get readyVersionOrPending => _version ?? '';

  DownloadResult? _lastResult;
  DownloadResult? get lastResult => _lastResult;

  UpdateService? _service;
  DownloadCancelToken? _cancelToken;

  List<DownloadAttempt> get lastAttempts => _service?.lastAttempts ?? const [];

  /// 启动时恢复此前下载好的安装包：仅当文件仍在、SHA256 通过、且记录版本
  /// 仍高于当前运行版本时，标记为"可安装"。否则清理记录（含文件）。
  Future<void> restore(AppBuildInfo current, UpdateService service) async {
    if (_status == InstallerStatus.downloading) return;
    final data = await _storage.load(_recordKey);
    if (data is! Map) return;
    final version = data['version'] as String?;
    final buildNumber = (data['buildNumber'] as num?)?.toInt();
    final filePath = data['filePath'] as String?;
    final sha = data['sha256'] as String? ?? '';
    if (version == null || filePath == null) {
      await _storage.save(_recordKey, null);
      return;
    }
    // 当前版本已追上/超过记录版本 → 已安装或不再需要，清理。
    if ((buildNumber ?? 0) <= current.buildNumber) {
      await _clearRecord(service, filePath);
      return;
    }
    // 文件需仍存在且校验通过才认为可安装。
    final valid = await service.verifySha256(filePath, sha);
    if (!valid) {
      await _clearRecord(service, filePath);
      return;
    }
    _version = version;
    _filePath = filePath;
    _service = service;
    _status = InstallerStatus.readyToInstall;
    notifyListeners();
  }

  /// 开始下载（应用内常驻，切页不中断）。
  Future<void> startDownload({
    required UpdateService service,
    required PlatformUpdate platformUpdate,
    required String version,
    required int buildNumber,
  }) async {
    if (_status == InstallerStatus.downloading) return;
    _service = service;
    _status = InstallerStatus.downloading;
    _version = version;
    _received = 0;
    _total = platformUpdate.size;
    _source = '';
    _lastResult = null;
    _cancelToken = DownloadCancelToken();
    notifyListeners();

    final (filePath, result) = await service.downloadUpdate(
      platformUpdate: platformUpdate,
      version: version,
      cancelToken: _cancelToken,
      onProgress: (r, t, s) {
        _received = r;
        _total = t;
        _source = s;
        notifyListeners();
      },
    );

    _lastResult = result;
    _cancelToken = null;
    if (result == DownloadResult.success && filePath != null) {
      _filePath = filePath;
      _status = InstallerStatus.readyToInstall;
      // 持久化已校验安装包记录，供"再次打开安装"使用。
      await _storage.save(_recordKey, {
        'version': version,
        'buildNumber': buildNumber,
        'filePath': filePath,
        'sha256': platformUpdate.sha256,
      });
    } else if (result == DownloadResult.cancelled) {
      _status = InstallerStatus.idle;
    } else {
      _status = InstallerStatus.failed;
    }
    notifyListeners();
  }

  /// 取消进行中的下载。
  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    if (_status == InstallerStatus.downloading) {
      _status = InstallerStatus.idle;
      notifyListeners();
    }
  }

  /// 打开已下载安装包，启动系统安装流程。
  Future<bool> install() async {
    final path = _filePath;
    final service = _service;
    if (path == null || service == null) return false;
    return service.openInstaller(path);
  }

  /// 用户主动放弃这次更新：清掉记录与文件，回到 idle。
  Future<void> discard() async {
    final service = _service;
    final path = _filePath;
    if (service != null && path != null) {
      await _clearRecord(service, path);
    } else {
      await _storage.save(_recordKey, null);
    }
    _status = InstallerStatus.idle;
    _version = null;
    _filePath = null;
    notifyListeners();
  }

  Future<void> _clearRecord(UpdateService service, String filePath) async {
    await _storage.save(_recordKey, null);
    await service.deleteFileQuietly(filePath);
  }
}
