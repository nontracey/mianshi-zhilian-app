@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';
import 'package:http/io_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/application/coach_agent.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/model/compat_gateway.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'package:mianshi_zhilian/services/coach_http_client.dart';
import 'package:mianshi_zhilian/services/coach_rules_loader.dart';
import '../coach/implementation_flows_test.dart' show seed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = Platform.environment['COACH_LIVE_API_KEY'];
  test(
    'live Agnes teaching and interview use real coach context and durable originals',
    () async {
      HttpOverrides.global = null;
      final http = CoachHttpClient(
        client: IOClient(
          HttpClient()..findProxy = HttpClient.findProxyFromEnvironment,
        ),
      );
      addTearDown(http.close);
      final gateway = OpenAiCompatibleGateway(
        baseUrl: 'https://apihub.agnes-ai.com/v1',
        apiKey: key!,
        model: 'agnes-2.0-flash',
        http: http,
      );
      final binding = CoachModelBinding(
        gateway: gateway,
        providerConfigId: 'live-agnes',
        probe: gateway.probe,
      );
      final store = InMemoryCoachStore();
      await seed(store);
      final coach = CoachProvider(
        store: store,
        profileId: 'p',
        modelBindingProvider: () => binding,
        rulesProvider: CoachRulesLoader().load,
      );
      await coach.load();
      await coach.startSession(
        mode: SessionMode.learning,
        knowledgeItemId: 'k',
        reviewPointId: 'rp',
      );
      final lesson = await coach.generateCurrentReply();
      expect(lesson.structured, isTrue);
      expect(lesson.message.content.trim(), isNotEmpty);
      expect(
        (await store.getReviewState('rp'))!.consecutiveIndependentPasses,
        0,
      );
      await coach.startSession(
        mode: SessionMode.interview,
        knowledgeItemId: 'k',
        reviewPointId: 'rp',
        maxQuestions: 1,
      );
      final question = await coach.generateCurrentReply();
      expect(question.structured, isTrue);
      expect(question.message.references, contains('reviewPoint:rp'));
      await coach.sendUserMessage(
        'Synthetic answer: a mutex serializes access to the shared state; execution order across threads is otherwise not guaranteed.',
      );
      expect(
        coach.messages.any(
          (m) => m.role == 'user' && m.content.startsWith('Synthetic answer:'),
        ),
        isTrue,
      );
      expect(coach.activeSession!.status, RuntimeStatus.completed);
      final records = await store.listAssessmentEvents(coach.activeSession!.id);
      expect(
        records.every((e) => e.validity == EvidenceValidity.pending),
        isTrue,
        reason:
            'This synthetic scope has no trusted reference; it cannot award verified credit',
      );
      if (Platform.environment['COACH_LIVE_REPORT'] case final String path) {
        File(path).writeAsStringSync(
          jsonEncode({
            'model': 'agnes-2.0-flash',
            'lesson': lesson.message.content,
            'question': question.message.content,
            'closing': coach.messages.last.content,
            'structured': true,
            'assessmentCount': records.length,
            'finished': true,
          }),
        );
      }
    },
    skip: key == null ? 'Explicit live test key not supplied' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
