import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/providers/update_download_provider.dart';
import 'package:mianshi_zhilian/services/app_version_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';

/// 验证"已下载安装包"恢复/清理逻辑：文件仍在 + 版本仍新才显示可安装入口，
/// 否则清理记录与文件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late UpdateService service;
  late Directory tmp;

  AppBuildInfo current() =>
      const AppBuildInfo(version: '0.1.0', buildNumber: 100);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    service = UpdateService();
    tmp = await Directory.systemTemp.createTemp('installer_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> writeInstaller(String name, String content) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsString(content);
    return f.path;
  }

  String sha256Of(String content) => sha256.convert(content.codeUnits).toString();

  test('restore with no record stays idle', () async {
    final p = UpdateDownloadProvider(storage);
    await p.restore(current(), service);
    expect(p.status, InstallerStatus.idle);
    expect(p.readyVersion, isNull);
  });

  test('restore clears record when build number is not newer', () async {
    final path = await writeInstaller('mianshi-zhilian-v0.1.0.apk', 'abc');
    await storage.save('downloaded_installer', {
      'version': '0.1.0',
      'buildNumber': 100, // 等于当前 → 视为已安装/无需
      'filePath': path,
      'sha256': sha256Of('abc'),
    });

    final p = UpdateDownloadProvider(storage);
    await p.restore(current(), service);

    expect(p.status, InstallerStatus.idle);
    expect(await storage.load('downloaded_installer'), isNull);
    expect(await File(path).exists(), isFalse, reason: '过期安装包应被删除');
  });

  test('restore marks ready when file valid and version newer', () async {
    const content = 'installer-bytes';
    final path = await writeInstaller('mianshi-zhilian-v0.2.0.apk', content);
    await storage.save('downloaded_installer', {
      'version': '0.2.0',
      'buildNumber': 200,
      'filePath': path,
      'sha256': sha256Of(content),
    });

    final p = UpdateDownloadProvider(storage);
    await p.restore(current(), service);

    expect(p.status, InstallerStatus.readyToInstall);
    expect(p.readyVersion, '0.2.0');
    expect(p.filePath, path);
  });

  test('restore clears record when sha256 mismatches', () async {
    final path = await writeInstaller('mianshi-zhilian-v0.2.0.apk', 'real');
    await storage.save('downloaded_installer', {
      'version': '0.2.0',
      'buildNumber': 200,
      'filePath': path,
      'sha256': sha256Of('different'), // 不匹配
    });

    final p = UpdateDownloadProvider(storage);
    await p.restore(current(), service);

    expect(p.status, InstallerStatus.idle);
    expect(await storage.load('downloaded_installer'), isNull);
  });

  test('discard clears record, file, and resets to idle', () async {
    const content = 'bytes';
    final path = await writeInstaller('mianshi-zhilian-v0.2.0.apk', content);
    await storage.save('downloaded_installer', {
      'version': '0.2.0',
      'buildNumber': 200,
      'filePath': path,
      'sha256': sha256Of(content),
    });

    final p = UpdateDownloadProvider(storage);
    await p.restore(current(), service);
    expect(p.status, InstallerStatus.readyToInstall);

    await p.discard();
    expect(p.status, InstallerStatus.idle);
    expect(p.readyVersion, isNull);
    expect(await storage.load('downloaded_installer'), isNull);
    expect(await File(path).exists(), isFalse);
  });
}
