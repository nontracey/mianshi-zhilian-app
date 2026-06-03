import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/whisper_stt_service.dart';

class _MockClient extends http.BaseClient {
  _MockClient(this.statusCode, this.body);

  final int statusCode;
  final String body;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}

void main() {
  group('WhisperSttService', () {
    test('transcribe sends request to correct URL and returns response body', () async {
      final mock = _MockClient(200, 'Hello world');
      final service = WhisperSttService(client: mock);

      final result = await service.transcribe(
        audioBytes: Uint8List(0),
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
      );

      expect(result, 'Hello world');
      expect(mock.requests, hasLength(1));
      final req = mock.requests[0];
      expect(req.url.toString(),
          'https://api.openai.com/v1/audio/transcriptions');
      expect(req.headers['authorization'], 'Bearer sk-test');
    });

    test('transcribe strips trailing slashes from base URL', () async {
      final mock = _MockClient(200, 'ok');
      final service = WhisperSttService(client: mock);

      await service.transcribe(
        audioBytes: Uint8List(0),
        baseUrl: 'https://api.openai.com/v1/',
        apiKey: 'sk-test',
      );

      final req = mock.requests[0];
      expect(req.url.toString(),
          'https://api.openai.com/v1/audio/transcriptions');
    });

    test('transcribe throws on non-200 response', () async {
      final mock = _MockClient(500, 'Internal Server Error');
      final service = WhisperSttService(client: mock);

      expect(
        () => service.transcribe(
          audioBytes: Uint8List(0),
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Whisper transcription failed: HTTP 500'),
        )),
      );
    });

    test('transcribe includes model and language in multipart request body', () async {
      final mock = _MockClient(200, 'ok');
      final service = WhisperSttService(client: mock);

      await service.transcribe(
        audioBytes: Uint8List.fromList([0x00, 0x01]),
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'whisper-1',
        language: 'en',
        fileName: 'test.wav',
      );

      final req = mock.requests[0];
      // Verify URL
      expect(req.url.toString(),
          'https://api.openai.com/v1/audio/transcriptions');

      // Verify body contains expected form fields
      final multipartReq = req as http.MultipartRequest;
      final bodyBytes = await multipartReq.finalize().toBytes();
      final bodyStr = utf8.decode(bodyBytes);
      expect(bodyStr, contains('name="model"'));
      expect(bodyStr, contains('whisper-1'));
      expect(bodyStr, contains('name="language"'));
      expect(bodyStr, contains('en'));
      expect(bodyStr, contains('name="file"'));
    });
  });
}