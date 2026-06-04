import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';

void main() {
  test('bulk paste parser extracts url key and model', () {
    final parsed = parseAiConfigPaste('''
https://api.example.com/v1
sk-test-key
deepseek-chat
''');

    expect(parsed.baseUrl, 'https://api.example.com/v1');
    expect(parsed.apiKey, 'sk-test-key');
    expect(parsed.model, 'deepseek-chat');
  });

  test('bulk paste parser supports key value format', () {
    final parsed = parseAiConfigPaste('''
base_url=https://open.bigmodel.cn/api/paas/v4
api_key=ak-test
model=glm-4-flash
''');

    expect(parsed.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    expect(parsed.apiKey, 'ak-test');
    expect(parsed.model, 'glm-4-flash');
  });

  test(
    'bulk paste parser handles unrecognized api key prefix via position',
    () {
      final parsed = parseAiConfigPaste('''
https://api.example.com/v1
my-custom-api-key-12345
my-model-name
''');

      expect(parsed.baseUrl, 'https://api.example.com/v1');
      expect(parsed.apiKey, 'my-custom-api-key-12345');
      expect(parsed.model, 'my-model-name');
    },
  );
}
