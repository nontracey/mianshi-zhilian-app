/// 确定性 Mock 网关，只在测试里使用（§8.1 未配置模型时不得伪装成真实回答）。
///
/// 不连接任何网络；其行为完全由 [responder] 或默认脚本决定，便于测试。
library;

import 'package:mianshi_zhilian/coach/model/errors.dart';
import 'package:mianshi_zhilian/coach/model/gateway.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/coach/model/messages.dart';

/// 默认脚本响应：回显最后一条用户消息，并给出一个中性教学式回答。
ModelGatewayResponse _defaultRespond(ModelGatewayRequest request) {
  final lastUser = request.messages.lastWhere(
    (m) => m.role == ChatRole.user,
    orElse: () => request.messages.last,
  );
  final content =
      '（演示模型）收到：${lastUser.content}\n'
      '这是离线占位回答，未连接真实模型。请在“设置”中配置教练模型以获得智能教学与评分。';
  return ModelGatewayResponse(
    message: ChatMessage.assistant(content: content),
    providerConfigId: 'mock',
    model: 'mock-coach',
  );
}

class MockModelGateway implements ModelGateway {
  MockModelGateway({
    this.responder = _defaultRespond,
    ModelCapabilities? capabilities,
  }) : capabilities =
           capabilities ??
           ModelCapabilities(
             supportsStreaming: true,
             supportsTools: true,
             supportsJsonResponse: true,
             detectedModel: 'mock-coach',
             notes: ['未连接真实模型，仅用于离线验证'],
           );

  /// 自定义响应脚本；不提供时使用默认回显。
  final ModelGatewayResponse Function(ModelGatewayRequest) responder;

  final ModelCapabilities capabilities;

  /// 捕获的 complete 请求（按序），供断言请求装配（§8.1 能力降级）使用。
  final List<ModelGatewayRequest> requests = [];

  @override
  Future<ModelGatewayResponse> complete(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw ModelCanceledException();
    }
    requests.add(request);
    return responder(request);
  }

  @override
  Stream<ModelStreamEvent> stream(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  }) async* {
    if (cancel?.isCancelled ?? false) return;
    final resp = responder(request);
    final content = resp.message.content;
    // 按句子/字符分块模拟流式增量。
    final chunks = content.split(RegExp(r'(?<=\n)|(?<=。)|(?<=；)'))
      ..removeWhere((c) => c.isEmpty);
    for (final chunk in chunks) {
      if (cancel?.isCancelled ?? false) return;
      yield ModelStreamEvent(deltaContent: chunk);
    }
    yield ModelStreamEvent(isDone: true, usage: resp.usage);
  }

  @override
  Future<ModelCapabilities> probe() async => capabilities;
}
