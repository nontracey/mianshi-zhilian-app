import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mianshi_zhilian/coach/model/compat_gateway.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/services/coach_http_client.dart';
import 'package:mianshi_zhilian/services/coach_model_binding.dart';

void main() {
  test('configured default has priority over an earlier verified model', () {
    final first = AiConfig(
      id: 'first',
      name: 'first',
      baseUrl: 'https://a.test/v1',
      apiKey: 'key',
      model: 'a',
      supportsTextInput: true,
      capabilityTests: const {
        'text': CapabilityTestRecord(state: CapabilityTestState.passed),
      },
    );
    final preferred = first.copyWith(id: 'preferred', name: 'preferred');
    expect(defaultCoachConfig([first, preferred], preferred)?.id, 'preferred');
  });

  test(
    'probe tests JSON mode and temperature separately from a greeting',
    () async {
      final requests = <Map<String, dynamic>>[];
      final transport = CoachHttpClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          if (body.containsKey('temperature')) return http.Response('{}', 400);
          if (body['stream'] == true)
            return http.Response('data: [DONE]\n\n', 200);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': body.containsKey('response_format')
                        ? '{"ok":true}'
                        : 'hello',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final gateway = OpenAiCompatibleGateway(
        baseUrl: 'https://a.test/v1',
        apiKey: 'key',
        model: 'a',
        http: transport,
      );
      final caps = await gateway.probe();
      expect(caps.supportsJsonResponse, isTrue);
      expect(caps.supportsTemperature, isFalse);
      expect(caps.supportsTools, isFalse);
      expect(
        requests.where((r) => r.containsKey('response_format')),
        hasLength(1),
      );
      expect(requests.where((r) => r.containsKey('temperature')), hasLength(1));
    },
  );
}
