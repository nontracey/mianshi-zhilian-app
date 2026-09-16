/// 兼容 OpenAI `/chat/completions` 的模型网关（§8.1 统一多轮消息、流式、工具调用、能力探测）。
///
/// 只依赖抽象的 [HttpClient]，不在客户端硬编码任何厂商专属参数。
/// 不支持原生 tools 的模型：本网关仍会发送 tools，调用方若需降级可在外层包一层
/// “受限 JSON 提案”适配器（本文件不内置，保持网关语义清晰）。
library;

import 'dart:convert';

import 'errors.dart';
import 'gateway.dart';
import 'http_client.dart';
import 'messages.dart';

class OpenAiCompatibleGateway implements ModelGateway {
  OpenAiCompatibleGateway({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.http,
    this.headersProvider,
    this.providerConfigId,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final HttpClient http;
  final Map<String, String> Function()? headersProvider;
  final String? providerConfigId;

  String get _chatUrl {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$trimmed/chat/completions';
  }

  Map<String, String> _headers() {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    if (headersProvider != null) h.addAll(headersProvider!());
    return h;
  }

  Map<String, dynamic> _buildBody(
    ModelGatewayRequest request, {
    required bool stream,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'messages': ChatMessage.toWireBatch(request.messages),
      'stream': stream,
    };
    if (request.temperature != null) body['temperature'] = request.temperature;
    // OpenAI 使用 max_tokens；其他兼容实现多数接受同名字段。
    if (request.maxTokens != null) body['max_tokens'] = request.maxTokens;
    if (request.responseFormatJson) {
      body['response_format'] = {'type': 'json_object'};
    }
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!.map((t) => t.toJson()).toList();
      body['tool_choice'] = 'auto';
    }
    return body;
  }

  @override
  Future<ModelGatewayResponse> complete(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw ModelCanceledException();
    final body = _buildBody(request, stream: false);
    final encoded = jsonEncode(body);
    final timeout = Duration(milliseconds: request.timeoutMs);
    final resp = await http
        .post(_chatUrl, headers: _headers(), body: encoded, cancel: cancel)
        .timeout(timeout, onTimeout: () => throw ModelTimeoutException());
    if (cancel?.isCancelled ?? false) throw ModelCanceledException();
    return _toResponse(resp);
  }

  ModelGatewayResponse _toResponse(HttpResponse resp) {
    if (resp.statusCode == 401) throw ModelAuthException();
    if (resp.statusCode == 429) throw ModelRateLimitException();
    if (!resp.isOk) {
      throw ModelGatewayException(
        '模型返回错误',
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final choice =
        (json['choices'] as List<dynamic>).first as Map<String, dynamic>;
    final message = _parseMessage(choice['message'] as Map<String, dynamic>);
    final usage = _parseUsage(json['usage'] as Map<String, dynamic>?);
    return ModelGatewayResponse(
      message: message,
      usage: usage,
      model: json['model'] as String? ?? model,
      raw: json,
      providerConfigId: providerConfigId,
    );
  }

  @override
  Stream<ModelStreamEvent> stream(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  }) async* {
    if (cancel?.isCancelled ?? false) throw ModelCanceledException();
    final body = _buildBody(request, stream: true);
    final encoded = jsonEncode(body);
    final timeout = Duration(milliseconds: request.timeoutMs);
    final deadline = DateTime.now().add(timeout);
    final chunks = http.postStreaming(
      _chatUrl,
      headers: _headers(),
      body: encoded,
      cancel: cancel,
    );

    String buffer = '';
    ModelUsage? usage;
    final toolAccum = <int, _ToolAccum>{};
    await for (final chunk in chunks.timeout(
      timeout,
      onTimeout: (sink) {
        sink.addError(ModelTimeoutException());
        sink.close();
      },
    )) {
      if (cancel?.isCancelled ?? false) throw ModelCanceledException();
      if (DateTime.now().isAfter(deadline)) throw ModelTimeoutException();
      buffer += chunk;
      // 按 SSE 事件边界拆分（\n\n），逐条处理完整事件。
      final events = buffer.split(RegExp(r'\r?\n\r?\n'));
      buffer = events.removeLast();
      for (final rawEvent in events) {
        final data = _extractData(rawEvent);
        if (data == null) continue;
        if (data == '[DONE]') {
          yield ModelStreamEvent(
            isDone: true,
            usage: usage,
            toolCalls: _finalizeToolCalls(toolAccum),
          );
          return;
        }
        final parsed = _parseStreamDelta(data, toolAccum);
        if (parsed.usage != null) usage = parsed.usage;
        if (parsed.event != null) yield parsed.event!;
      }
    }
    if (_extractData(buffer) == '[DONE]') {
      yield ModelStreamEvent(
        isDone: true,
        usage: usage,
        toolCalls: _finalizeToolCalls(toolAccum),
      );
      return;
    }
    throw ModelGatewayException('模型响应提前中断，尚未完成');
  }

  String? _extractData(String rawEvent) {
    final lines = rawEvent
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trimLeft())
        .toList();
    return lines.isEmpty ? null : lines.join('\n');
  }

  ({ModelStreamEvent? event, ModelUsage? usage}) _parseStreamDelta(
    String data,
    Map<int, _ToolAccum> toolAccum,
  ) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      return (
        event: null,
        usage: _parseUsage(json['usage'] as Map<String, dynamic>?),
      );
    }
    final choice = choices.first as Map<String, dynamic>;
    final deltaMap = choice['delta'] as Map<String, dynamic>? ?? {};
    final content = deltaMap['content'] as String?;
    ModelStreamEvent? event;
    if (content != null && content.isNotEmpty) {
      event = ModelStreamEvent(deltaContent: content);
    }
    final toolCallsJson = deltaMap['tool_calls'] as List<dynamic>?;
    if (toolCallsJson != null) {
      // 工具调用分片只在本地累积，不在此 yield 空事件；
      // 流结束时的聚合结果通过 done 事件的 toolCalls 字段交付。
      for (final tc in toolCallsJson) {
        final m = tc as Map<String, dynamic>;
        final index = m['index'] as int? ?? 0;
        final acc = toolAccum.putIfAbsent(index, () => _ToolAccum());
        if (m['id'] != null) acc.id = m['id'] as String;
        if (m['function'] != null) {
          final fn = m['function'] as Map<String, dynamic>;
          if (fn['name'] != null) acc.name = fn['name'] as String;
          if (fn['arguments'] != null) {
            acc.argsBuffer += fn['arguments'] as String;
          }
        }
      }
    }
    final usageJson = json['usage'] as Map<String, dynamic>?;
    ModelUsage? usage;
    if (usageJson != null) {
      usage = _parseUsage(usageJson);
      event ??= ModelStreamEvent(deltaContent: '', usage: usage);
    }
    return (event: event, usage: usage);
  }

  /// 收集流式工具调用，聚合成完整 [ToolCall] 列表（流结束时调用）。
  List<ToolCall> _finalizeToolCalls(Map<int, _ToolAccum> accum) {
    final sorted = accum.keys.toList()..sort();
    return sorted.map((i) {
      final acc = accum[i]!;
      Map<String, dynamic> arguments = {};
      if (acc.argsBuffer.trim().isNotEmpty) {
        try {
          arguments = Map<String, dynamic>.from(jsonDecode(acc.argsBuffer));
        } catch (_) {
          throw ModelGatewayException('工具参数不是完整 JSON 对象');
        }
      }
      if (acc.id.isEmpty || acc.name.isEmpty) {
        throw ModelGatewayException('工具调用缺少标识');
      }
      return ToolCall(id: acc.id, name: acc.name, arguments: arguments);
    }).toList();
  }

  @override
  Future<ModelCapabilities> probe() async {
    final notes = <String>[];
    var supportsStreaming = false;
    var supportsTools = false;
    var supportsJsonResponse = false;
    var supportsTemperature = false;
    String? detectedModel;

    // 1) 文本能力：发一条最简消息。
    try {
      final resp = await complete(
        ModelGatewayRequest(
          messages: [ChatMessage.system('ping'), ChatMessage.user('hi')],
          stream: false,
          timeoutMs: 20000,
        ),
      );
      detectedModel = resp.model;
    } catch (e) {
      rethrow;
    }

    // Probe optional parameters independently: a normal greeting says nothing
    // about JSON mode, and some models reject temperature entirely.
    try {
      final response = await complete(
        ModelGatewayRequest(
          messages: [
            ChatMessage.user('Return only this JSON object: {"ok":true}'),
          ],
          responseFormatJson: true,
          timeoutMs: 20000,
        ),
      );
      supportsJsonResponse = _looksLikeJson(response.message.content);
    } catch (_) {
      notes.add('JSON response format unavailable');
    }
    try {
      await complete(
        ModelGatewayRequest(
          messages: [ChatMessage.user('Reply OK')],
          temperature: 0.25,
          timeoutMs: 20000,
        ),
      );
      supportsTemperature = true;
    } catch (_) {
      notes.add('Custom temperature unavailable');
    }

    // 2) 流式能力：尝试一次流式，能收到增量即认为支持。
    try {
      final streamed = stream(
        ModelGatewayRequest(
          messages: [ChatMessage.user('hi')],
          stream: true,
          timeoutMs: 20000,
        ),
      );
      await for (final _ in streamed) {
        supportsStreaming = true;
        break;
      }
    } catch (e) {
      notes.add('流式探测失败，可降级为非流式：$e');
    }

    // 3) 工具能力：给一个无害工具，看模型是否返回 tool_calls。
    try {
      final toolResp = await complete(
        ModelGatewayRequest(
          messages: [ChatMessage.user('现在几点？用 get_time 工具回答')],
          tools: [
            ToolSpec(
              name: 'get_time',
              description: '返回当前时间',
              parameters: {
                'type': 'object',
                'properties': <String, dynamic>{},
                'required': <String>[],
              },
            ),
          ],
          timeoutMs: 20000,
        ),
      );
      supportsTools = toolResp.message.toolCalls?.isNotEmpty ?? false;
    } catch (e) {
      notes.add('工具探测失败，当前配置不能使用原生工具调用：$e');
    }

    return ModelCapabilities(
      supportsStreaming: supportsStreaming,
      supportsTools: supportsTools,
      supportsJsonResponse: supportsJsonResponse,
      supportsTemperature: supportsTemperature,
      providerConfigId: providerConfigId,
      detectedModel: detectedModel,
      notes: notes,
    );
  }

  bool _looksLikeJson(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        jsonDecode(trimmed);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}

class _ToolAccum {
  String id = '';
  String name = '';
  String argsBuffer = '';
}

ChatMessage _parseMessage(Map<String, dynamic> json) {
  final content = (json['content'] as String?) ?? '';
  final toolCallsJson = json['tool_calls'] as List<dynamic>?;
  List<ToolCall>? toolCalls;
  if (toolCallsJson != null) {
    toolCalls = toolCallsJson.map((tc) {
      final m = tc as Map<String, dynamic>;
      final fn = m['function'] as Map<String, dynamic>;
      Map<String, dynamic> args = {};
      final raw = fn['arguments'] as String? ?? '{}';
      try {
        args = Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {
        throw ModelGatewayException('工具参数不是完整 JSON 对象');
      }
      return ToolCall(
        id: m['id'] as String? ?? '',
        name: fn['name'] as String? ?? '',
        arguments: args,
      );
    }).toList();
  }
  return ChatMessage(
    role: ChatRole.assistant,
    content: content,
    toolCalls: toolCalls,
  );
}

ModelUsage? _parseUsage(Map<String, dynamic>? json) {
  if (json == null) return null;
  return ModelUsage(
    promptTokens: json['prompt_tokens'] as int?,
    completionTokens: json['completion_tokens'] as int?,
    totalTokens: json['total_tokens'] as int?,
  );
}
