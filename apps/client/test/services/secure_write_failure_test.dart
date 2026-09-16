import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native secure-store failure never writes API keys to preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        StorageService.writeFailure.value = null;
      });
      final storage = StorageService();
      await expectLater(
        storage.saveAiConfigs([
          const AiConfig(
            id: 'synthetic',
            name: 'Synthetic',
            baseUrl: 'https://synthetic.invalid',
            apiKey: 'synthetic-never-persist',
            model: 'synthetic',
          ),
        ]),
        throwsA(isA<StorageWriteException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().map(prefs.get).join(),
        isNot(contains('synthetic-never-persist')),
      );
    },
  );
}
