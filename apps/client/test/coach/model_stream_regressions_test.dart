import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/model/compat_gateway.dart';
import 'package:mianshi_zhilian/coach/model/errors.dart';
import 'package:mianshi_zhilian/coach/model/gateway.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/coach/model/messages.dart';

class StreamHttp implements HttpClient {
  StreamHttp(this.chunks);
  final Stream<String> chunks;
  @override
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) => throw UnimplementedError();
  @override
  Stream<String> postStreaming(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) => chunks;
}

void main() {
  OpenAiCompatibleGateway gateway(Stream<String> chunks) =>
      OpenAiCompatibleGateway(
        baseUrl: 'https://synthetic.invalid/v1',
        apiKey: 'synthetic',
        model: 'synthetic',
        http: StreamHttp(chunks),
      );
  ModelGatewayRequest request({int timeoutMs = 500}) => ModelGatewayRequest(
    messages: [ChatMessage.user('synthetic')],
    timeoutMs: timeoutMs,
  );
  String event(Map<String, Object?> data) =>
      'data: ${jsonEncode(data)}\r\n\r\n';

  test(
    'CRLF split across chunks and usage-only choices are accepted',
    () async {
      final text =
          event({
            'choices': [
              {
                'delta': {'content': 'hello'},
              },
            ],
          }) +
          event({
            'choices': [],
            'usage': {'total_tokens': 12},
          }) +
          'data: [DONE]\r\n\r\n';
      final events = await gateway(
        Stream.fromIterable(text.split('')),
      ).stream(request()).toList();
      expect(
        events
            .where((e) => e.deltaContent != null)
            .map((e) => e.deltaContent)
            .join(),
        'hello',
      );
      expect(events.last.usage?.totalTokens, 12);
      expect(events.last.isDone, isTrue);
    },
  );

  test('truncated stream cannot report successful completion', () async {
    await expectLater(
      gateway(
        Stream.value(
          event({
            'choices': [
              {
                'delta': {'content': 'partial'},
              },
            ],
          }),
        ),
      ).stream(request()).toList(),
      throwsA(isA<ModelGatewayException>()),
    );
  });

  test('malformed tool parameters cannot become executable calls', () async {
    final chunk = event({
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'id': 'c',
                'function': {'name': 'lookup', 'arguments': '{'},
              },
            ],
          },
        },
      ],
    });
    await expectLater(
      gateway(
        Stream.fromIterable([chunk, 'data: [DONE]\n\n']),
      ).stream(request()).toList(),
      throwsA(isA<ModelGatewayException>()),
    );
  });

  test('silent transport times out even without a first chunk', () async {
    final controller = StreamController<String>();
    addTearDown(controller.close);
    await expectLater(
      gateway(controller.stream).stream(request(timeoutMs: 10)).toList(),
      throwsA(isA<ModelTimeoutException>()),
    );
  });
}
