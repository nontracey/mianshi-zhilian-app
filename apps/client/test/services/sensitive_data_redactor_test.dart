import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/sensitive_data_redactor.dart';

void main() {
  group('SensitiveDataRedactor', () {
    test('redacts common API keys, tokens, and authorization values', () {
      final googleKey = 'AIza${List.filled(35, 'A').join()}';
      final text = SensitiveDataRedactor.redact(
        'api_key="custom-secret-token-12345" '
        'Authorization: Bearer ya29.secret-token-value '
        'url=https://example.com/cb?access_token=abcdef1234567890 '
        'gemini=$googleKey',
      );

      expect(text, contains('api_key="[redacted]"'));
      expect(text, contains('Authorization: Bearer [redacted]'));
      expect(text, contains('access_token=[redacted]'));
      expect(text, contains('gemini=AIza***'));
      expect(text, isNot(contains('custom-secret-token-12345')));
      expect(text, isNot(contains('ya29.secret-token-value')));
      expect(text, isNot(contains('abcdef1234567890')));
    });

    test('redacts user names in common local filesystem paths', () {
      final text = SensitiveDataRedactor.redact(
        r'/Users/alice/Library/App Data '
        r'/home/bob/.cache '
        r'C:\Users\carol\AppData\Local',
      );

      expect(text, contains('/Users/[redacted]/Library'));
      expect(text, contains('/home/[redacted]/.cache'));
      expect(text, contains(r'C:\Users\[redacted]\AppData'));
      expect(text, isNot(contains('alice')));
      expect(text, isNot(contains('bob')));
      expect(text, isNot(contains('carol')));
    });
  });
}
