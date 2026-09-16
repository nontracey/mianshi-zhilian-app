import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用的内存版 flutter_secure_storage 平台通道。
///
/// 测试进程里没有真实钥匙串，所有安全写入都会失败；需要“安全存储可用”这条
/// 正常路径的用例（如 Whisper 配置迁移）必须先把通道替换掉，否则只能覆盖
/// 失败分支。
const MethodChannel secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 安装一个进程内的安全存储实现，并在测试结束后自动摘除。
void installFakeSecureStorage({Map<String, String> initial = const {}}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final values = Map<String, String>.from(initial);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'write':
        values[key!] = args['value'] as String;
        return null;
      case 'read':
        return values[key];
      case 'readAll':
        return Map<String, String>.from(values);
      case 'delete':
        values.remove(key);
        return null;
      case 'deleteAll':
        values.clear();
        return null;
      case 'containsKey':
        return values.containsKey(key);
    }
    throw MissingPluginException(
      'unsupported secure storage call: ${call.method}',
    );
  });

  addTearDown(() {
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    values.clear();
  });
}
