/// 统一模型网关契约与请求/响应模型（§8.1）。
///
/// 不同厂商的请求参数差异由 adapter 处理，不在教练页面硬编码。
/// 网关只负责：多轮消息、流式文本、工具调用消息及结果、结构化响应、
/// 超时、取消、usage 与错误分类。
library;

import 'http_client.dart';
import 'messages.dart';

/// 模型用量（没有 usage 时显示未知，不编造费用）。
class ModelUsage {
  ModelUsage({this.promptTokens, this.completionTokens, this.totalTokens});
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  ModelUsage merge(ModelUsage? other) {
    if (other == null) return this;
    return ModelUsage(
      promptTokens: other.promptTokens ?? promptTokens,
      completionTokens: other.completionTokens ?? completionTokens,
      totalTokens: other.totalTokens ?? totalTokens,
    );
  }
}

/// 网关返回的一次完整响应（非流式）。
class ModelGatewayResponse {
  ModelGatewayResponse({
    required this.message,
    this.usage,
    this.model,
    this.raw,
    this.providerConfigId,
  });

  final ChatMessage message;
  final ModelUsage? usage;
  final String? model;
  final String? providerConfigId;

  /// 原始响应体（调试/审计用，不进入评分权威字段）。
  final Map<String, dynamic>? raw;
}

/// 流式事件。
class ModelStreamEvent {
  ModelStreamEvent({
    this.deltaContent,
    this.deltaToolCall,
    this.isDone = false,
    this.usage,
    this.toolCalls,
  });

  /// 增量文本内容。
  final String? deltaContent;

  /// 增量工具调用（可能为分片）。
  final ToolCallDelta? deltaToolCall;

  /// 是否为流结束标记。
  final bool isDone;

  final ModelUsage? usage;

  /// 流结束时的聚合工具调用（由适配器拼接分片后填充）。
  final List<ToolCall>? toolCalls;
}

/// 流式工具调用分片。
class ToolCallDelta {
  ToolCallDelta({this.id, this.name, this.argumentsFragment});
  final String? id;
  final String? name;

  /// 增量参数字符串片段，需拼接后解析。
  final String? argumentsFragment;
}

/// 模型网关请求。
class ModelGatewayRequest {
  ModelGatewayRequest({
    required this.messages,
    this.tools,
    this.stream = false,
    this.temperature,
    this.maxTokens,
    this.responseFormatJson = false,
    this.timeoutMs = 90000,
  });

  final List<ChatMessage> messages;
  final List<ToolSpec>? tools;
  final bool stream;
  final double? temperature;
  final int? maxTokens;

  /// 是否请求 JSON 响应格式（不支持时由 adapter 降级）。
  final bool responseFormatJson;
  final int timeoutMs;
}

/// 模型能力探测结果（§8.1 实际能力探测）。
class ModelCapabilities {
  ModelCapabilities({
    this.supportsStreaming = false,
    this.supportsTools = false,
    this.supportsJsonResponse = false,
    this.supportsTemperature = false,
    this.providerConfigId,
    this.detectedModel,
    this.notes = const [],
  });

  final bool supportsStreaming;
  final bool supportsTools;
  final bool supportsJsonResponse;
  final bool supportsTemperature;
  final String? providerConfigId;
  final String? detectedModel;

  /// 探测过程中的补充说明（如“工具调用未验证，仅文本已验证”）。
  final List<String> notes;

  ModelCapabilities mergeNotes(List<String> extra) => ModelCapabilities(
    supportsStreaming: supportsStreaming,
    supportsTools: supportsTools,
    supportsJsonResponse: supportsJsonResponse,
    supportsTemperature: supportsTemperature,
    providerConfigId: providerConfigId,
    detectedModel: detectedModel,
    notes: [...notes, ...extra],
  );
}

/// 统一模型网关接口。本地代码通过它调用用户配置的在线 AI。
abstract class ModelGateway {
  /// 一次性完整响应。
  Future<ModelGatewayResponse> complete(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  });

  /// 流式响应。适配器负责 SSE/分片解析，并向外暴露增量事件。
  Stream<ModelStreamEvent> stream(
    ModelGatewayRequest request, {
    CancelToken? cancel,
  });

  /// 实际能力探测：分别测试文本/流式/工具/结构化能力，不凭聊天成功就认定工具可用。
  Future<ModelCapabilities> probe();
}
