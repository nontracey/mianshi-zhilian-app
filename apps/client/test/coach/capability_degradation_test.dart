/// §8.1 能力探测与降级：probe 结果驱动请求装配与提案修复。
///
/// 全部纯 Dart、不连网。验证四件事：
/// 1. 绑定的能力探测只做一次并缓存；
/// 2. `supportsJsonResponse=false` 时不请求 JSON 响应格式，也不做修复重试，
///    回答仍保留并如实标为未评估（structured=false）；
/// 3. `supportsTemperature=false` 时不发 temperature 参数；
/// 4. JSON 解析失败允许恰好一次修复；修复成功按结构化处理。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/application/coach_agent.dart';
import 'package:mianshi_zhilian/coach/application/coach_runtime.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/model/gateway.dart';
import 'package:mianshi_zhilian/coach/model/messages.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'fakes/mock_gateway.dart';

final DateTime now = DateTime(2026, 9, 12, 10);

void main() {
  CoachAgent buildAgent({
    required InMemoryCoachStore store,
    required ModelGateway gateway,
    required Future<ModelCapabilities> Function()? probe,
  }) {
    final runtime = CoachRuntime(
      store: store,
      idGen: IdGenerator(
        factory: (() {
          var i = 0;
          return () => 'id-${i++}';
        })(),
      ),
      clock: FixedClock(now),
    );
    return CoachAgent(
      store: store,
      runtime: runtime,
      modelBindingProvider: () => CoachModelBinding(
        gateway: gateway,
        providerConfigId: 'p1',
        probe: probe,
      ),
      rulesProvider: () async => const {},
    );
  }

  Future<(CoachAgent, SessionId)> prepareSession(CoachAgent agent) async {
    final session = await agent.runtime.startSession(
      profileId: 'p-default',
      mode: SessionMode.learning,
    );
    await agent.runtime.appendUserMessage(
      sessionId: session.id,
      content: 'HashMap 的底层原理是什么？',
    );
    return (agent, session.id);
  }

  test('能力探测只执行一次并缓存', () async {
    var probeCalls = 0;
    final binding = CoachModelBinding(
      gateway: MockModelGateway(),
      providerConfigId: 'p1',
      probe: () async {
        probeCalls++;
        return ModelCapabilities(supportsJsonResponse: true);
      },
    );
    final first = await binding.capabilities();
    final second = await binding.capabilities();
    expect(probeCalls, 1, reason: '每个绑定只探测一次');
    expect(identical(first, second), isTrue);
  });

  test(
    'transient probe failure does not poison cached binding forever',
    () async {
      var calls = 0;
      final binding = CoachModelBinding(
        gateway: MockModelGateway(),
        providerConfigId: 'p',
        probe: () async {
          if (++calls == 1) throw StateError('temporarily offline');
          return ModelCapabilities(supportsJsonResponse: true);
        },
      );
      await expectLater(binding.capabilities(), throwsStateError);
      expect((await binding.capabilities()).supportsJsonResponse, isTrue);
      expect(calls, 2);
    },
  );

  test('未提供探测时按保守默认值处理（纯文本）', () async {
    final binding = CoachModelBinding(
      gateway: MockModelGateway(),
      providerConfigId: 'p1',
    );
    final caps = await binding.capabilities();
    expect(caps.supportsJsonResponse, isFalse);
    expect(caps.supportsTools, isFalse);
    expect(caps.supportsStreaming, isFalse);
  });

  test('supportsJsonResponse=false：不请求 JSON、不修复、回答保留为未评估', () async {
    final store = InMemoryCoachStore();
    final gw = MockModelGateway(
      capabilities: ModelCapabilities(supportsJsonResponse: false),
      responder: (request) => ModelGatewayResponse(
        message: ChatMessage.assistant(content: '头插法是 JDK7 的实现细节。'),
      ),
    );
    final agent = buildAgent(store: store, gateway: gw, probe: gw.probe);
    final (agent_, sessionId) = await prepareSession(agent);

    final result = await agent_.run(sessionId);

    expect(gw.requests, hasLength(1), reason: '无 JSON 能力时不得做修复重试');
    expect(gw.requests.single.responseFormatJson, isFalse);
    expect(result.structured, isFalse, reason: '如实标注未评估');
    expect(result.assessmentCommitted, isFalse);
    expect(result.message.content, contains('头插法'));
  });

  test('supportsTemperature=false：请求不带 temperature', () async {
    final store = InMemoryCoachStore();
    final gw = MockModelGateway(
      capabilities: ModelCapabilities(
        supportsJsonResponse: true,
        supportsTemperature: false,
      ),
      responder: (request) => ModelGatewayResponse(
        message: ChatMessage.assistant(
          content: '{"assistantText":"尾插法解决了并发扩容的问题。"}',
        ),
      ),
    );
    final agent = buildAgent(store: store, gateway: gw, probe: gw.probe);
    final (agent_, sessionId) = await prepareSession(agent);

    final result = await agent_.run(sessionId);

    expect(result.structured, isTrue);
    for (final request in gw.requests) {
      expect(request.temperature, isNull);
    }
  });

  test('JSON 解析失败：恰好一次修复机会，修复成功按结构化处理', () async {
    final store = InMemoryCoachStore();
    var call = 0;
    final gw = MockModelGateway(
      capabilities: ModelCapabilities(supportsJsonResponse: true),
      responder: (request) {
        call++;
        // 第 1 次：完全没有 JSON 对象；第 2 次（修复）：合法提案。
        final content = call == 1
            ? '好的，我直接用文字回答：头插法会导致并发死循环。'
            : '{"assistantText":"修复后的回答正文","shouldCompleteSession":false}';
        return ModelGatewayResponse(
          message: ChatMessage.assistant(content: content),
        );
      },
    );
    final agent = buildAgent(store: store, gateway: gw, probe: gw.probe);
    final (agent_, sessionId) = await prepareSession(agent);

    final result = await agent_.run(sessionId);

    expect(gw.requests, hasLength(2), reason: '解析失败允许恰好一次修复');
    // 修复请求应包含上一条原始回答（作为 assistant 消息）。
    final repairMessages = gw.requests.last.messages;
    expect(repairMessages.any((m) => m.role == ChatRole.assistant), isTrue);
    expect(result.structured, isTrue);
    expect(result.message.content, '修复后的回答正文');
  });

  test('修复后仍失败：回答保留、如实标为未评估，不丢用户回合', () async {
    final store = InMemoryCoachStore();
    final gw = MockModelGateway(
      capabilities: ModelCapabilities(supportsJsonResponse: true),
      responder: (request) => ModelGatewayResponse(
        message: ChatMessage.assistant(content: '始终是纯文本回答。'),
      ),
    );
    final agent = buildAgent(store: store, gateway: gw, probe: gw.probe);
    final (agent_, sessionId) = await prepareSession(agent);

    final result = await agent_.run(sessionId);

    expect(gw.requests, hasLength(2));
    expect(result.structured, isFalse);
    expect(result.assessmentCommitted, isFalse);
    expect(result.message.content, '始终是纯文本回答。');
  });
  test('optional JSON repair failure preserves first model reply', () async {
    final store = InMemoryCoachStore();
    var calls = 0;
    final gateway = MockModelGateway(
      responder: (_) {
        if (++calls > 1) throw StateError('repair network failure');
        return ModelGatewayResponse(
          message: ChatMessage.assistant(content: 'Useful original reply'),
        );
      },
    );
    final agent = buildAgent(
      store: store,
      gateway: gateway,
      probe: () async => ModelCapabilities(supportsJsonResponse: true),
    );
    final (_, sessionId) = await prepareSession(agent);
    final result = await agent.run(sessionId);
    expect(result.message.content, 'Useful original reply');
    expect(result.assessmentCommitted, isFalse);
    expect(
      (await store.messagesOf(sessionId)).where((m) => m.role == 'user'),
      hasLength(1),
    );
  });
}
