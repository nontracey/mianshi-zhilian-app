/// 多轮消息、工具调用与结构化提案的纯数据模型（§7.2、§7.5）。
///
/// 模型可返回的“工具调用”和“结构化提案”都在此定义；本地代码负责校验
/// 参数合法性、权限与是否允许对外发送，模型只负责提出名称与参数。
library;

/// 消息角色。
enum ChatRole { system, user, assistant, tool }

extension ChatRoleX on ChatRole {
  String get wireName {
    switch (this) {
      case ChatRole.system:
        return 'system';
      case ChatRole.user:
        return 'user';
      case ChatRole.assistant:
        return 'assistant';
      case ChatRole.tool:
        return 'tool';
    }
  }
}

/// 工具调用。模型提出，本地执行后回填结果。
class ToolCall {
  ToolCall({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };
}

/// 工具规格（OpenAI 风格 JSON Schema）。供模型在 tools 字段中选用。
class ToolSpec {
  ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
    this.strict = false,
  });

  final String name;
  final String description;

  /// JSON Schema 对象，描述入参。
  final Map<String, dynamic> parameters;

  /// 是否启用严格模式（厂商支持时）。
  final bool strict;

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
      if (strict) 'strict': true,
    },
  };
}

/// 工具执行结果，回填到对话历史供模型继续。
class ToolResult {
  ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });

  final String toolCallId;
  final String content;
  final bool isError;

  ChatMessage toMessage() => ChatMessage.tool(
    toolCallId: toolCallId,
    content: content,
    isError: isError,
  );
}

/// 一轮对话中的一条消息。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.references = const [],
  });

  final ChatRole role;
  final String content;

  /// assistant 消息可能携带的工具调用。
  final List<ToolCall>? toolCalls;

  /// tool 角色消息对应的 toolCallId。
  final String? toolCallId;

  /// tool 角色消息对应的工具名称。
  final String? name;

  /// 检索增强引用的资料 ID（本地填充，不信任模型自报）。
  final List<String> references;

  factory ChatMessage.system(String content) =>
      ChatMessage(role: ChatRole.system, content: content);

  factory ChatMessage.user(String content) =>
      ChatMessage(role: ChatRole.user, content: content);

  factory ChatMessage.assistant({
    required String content,
    List<ToolCall>? toolCalls,
    List<String> references = const [],
  }) => ChatMessage(
    role: ChatRole.assistant,
    content: content,
    toolCalls: toolCalls,
    references: references,
  );

  factory ChatMessage.tool({
    required String toolCallId,
    required String content,
    String? name,
    bool isError = false,
  }) => ChatMessage(
    role: ChatRole.tool,
    content: isError ? '工具执行出错：$content' : content,
    toolCallId: toolCallId,
    name: name,
  );

  ChatMessage copyWith({String? content, List<String>? references}) =>
      ChatMessage(
        role: role,
        content: content ?? this.content,
        toolCalls: toolCalls,
        toolCallId: toolCallId,
        name: name,
        references: references ?? this.references,
      );

  Map<String, dynamic> toWireJson() {
    final Map<String, dynamic> json = {
      'role': role.wireName,
      'content': content,
    };
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (name != null) json['name'] = name;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!
          .map(
            (tc) => {
              'id': tc.id,
              'type': 'function',
              'function': {
                'name': tc.name,
                'arguments': _jsonString(tc.arguments),
              },
            },
          )
          .toList();
    }
    return json;
  }

  static List<Map<String, dynamic>> toWireBatch(List<ChatMessage> messages) =>
      messages.map((m) => m.toWireJson()).toList();
}

String _jsonString(Map<String, dynamic> map) {
  // 简单序列化；模型网关在真实网络传输时由 JSON 编码器处理。
  // 这里保证 tool_calls.arguments 为字符串，符合 OpenAI 线格式。
  return map.isEmpty ? '{}' : _encode(map);
}

String _encode(Map<String, dynamic> map) {
  final parts = map.entries
      .map((e) => '"${e.key}":${_encodeValue(e.value)}')
      .join(',');
  return '{$parts}';
}

String _encodeValue(dynamic v) {
  if (v is String) return '"${v.replaceAll('"', '\\"')}"';
  if (v is num || v is bool) return '$v';
  if (v == null) return 'null';
  if (v is List) {
    return '[${v.map(_encodeValue).join(',')}]';
  }
  if (v is Map) return _encode(v.cast<String, dynamic>());
  return '"$v"';
}
