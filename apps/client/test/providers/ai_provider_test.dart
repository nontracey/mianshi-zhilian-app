import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/services/ai_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAiService extends AiService {
  _FakeAiService(this.streams);

  final List<Stream<String>> streams;

  @override
  Stream<String> evaluateAnswerStream({
    required AiConfig config,
    required String topicTitle,
    required List<String> mustHave,
    required List<String> commonMistakes,
    required String userAnswer,
    required String language,
    Uint8List? imageBytes,
  }) {
    if (streams.isEmpty) return const Stream.empty();
    return streams.removeAt(0);
  }
}

AiConfig _textConfig() => AiConfig(
  id: 'ai-1',
  name: 'Test AI',
  baseUrl: 'https://api.example.test/v1',
  apiKey: 'sk-test',
  model: 'test-model',
  capabilityTests: {
    AiCapability.text.key: CapabilityTestRecord(
      state: CapabilityTestState.passed,
      testedAt: DateTime(2026),
    ),
  },
);

Future<AiProvider> _providerWith(
  List<Stream<String>> streams,
) async {
  SharedPreferences.setMockInitialValues({});
  final provider = AiProvider(_FakeAiService(streams), StorageService());
  await provider.addConfig(_textConfig());
  return provider;
}

void main() {
  test('stream parse failure is marked unavailable without a zero score', () async {
    final provider = await _providerWith([
      Stream.value('plain text, not json'),
    ]);

    final eval = provider.evaluateAnswerStream(
      topicId: 'topic-1',
      question: 'question',
      userAnswer: 'answer',
    );

    expect(await eval.stream.join(), 'plain text, not json');
    final result = await eval.result;

    expect(result['score'], isNull);
    expect(result['aiUnavailable'], isTrue);
  });

  test('starting a second stream completes the first call instead of hanging', () async {
    final first = StreamController<String>();
    final provider = await _providerWith([
      first.stream,
      Stream.value('{"score": 88, "summary": "ok"}'),
    ]);

    final firstEval = provider.evaluateAnswerStream(
      topicId: 'topic-1',
      question: 'question',
      userAnswer: 'answer',
    );
    final firstDone = firstEval.stream.drain<void>();

    final secondEval = provider.evaluateAnswerStream(
      topicId: 'topic-1',
      question: 'question',
      userAnswer: 'answer',
    );

    await firstDone.timeout(const Duration(seconds: 1));
    final cancelled = await firstEval.result.timeout(const Duration(seconds: 1));
    expect(cancelled['score'], isNull);
    expect(cancelled['aiUnavailable'], isTrue);

    final second = await secondEval.result;
    expect(second['score'], 88);
    expect(second['aiUnavailable'], isNot(isTrue));

    await first.close();
  });
}
