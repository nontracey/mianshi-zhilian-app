/// Remote MCP 2025-11-25 Streamable HTTP reader. Protocol annotations are
/// untrusted metadata; every tool requires explicit local authorization.
/// The newer per-request metadata protocol needs a separate adapter.
library;

import 'dart:async';
import 'dart:convert';

import '../model/http_client.dart';
import 'request_metadata.dart';

/// 支持的协议版本（§8.2：不照搬过时教程，按版本分支适配）。
abstract final class McpProtocolVersions {
  static const String v2025_11_25 = '2025-11-25';
  static const String v2026_07_28 = '2026-07-28';

  static bool isSupported(String? v) => v == v2025_11_25 || v == v2026_07_28;
}

/// 一台远程 MCP 服务的连接配置。
///
/// [token] 不随 [toJson] 落盘（进系统安全存储，由 Flutter 侧装配）。
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.protocolVersion = McpProtocolVersions.v2025_11_25,
    this.token,
    this.enabled = true,
    this.allowedTools = const [],
    this.allowSessionMaterials = false,
    this.oauthClientId,
    this.oauthScope,
  });

  final String id;
  final String name;
  final String url;
  final String protocolVersion;

  /// Bearer Token；不配置授权服务的服务可为空。
  final String? token;

  final bool enabled;

  /// 用户显式放行的工具名。名称相同的不同服务按服务隔离，不做全局放行。
  final List<String> allowedTools;

  /// Explicit permission for tool arguments derived from the current session.
  final bool allowSessionMaterials;
  final String? oauthClientId;
  final String? oauthScope;

  McpServerConfig copyWith({String? token, bool? enabled}) => McpServerConfig(
    id: id,
    name: name,
    url: url,
    protocolVersion: protocolVersion,
    token: token ?? this.token,
    enabled: enabled ?? this.enabled,
    allowedTools: allowedTools,
    allowSessionMaterials: allowSessionMaterials,
    oauthClientId: oauthClientId,
    oauthScope: oauthScope,
  );

  /// 持久化形态：不含 token。
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'protocolVersion': protocolVersion,
    'enabled': enabled,
    'allowedTools': allowedTools,
    'allowSessionMaterials': allowSessionMaterials,
    'oauthClientId': oauthClientId,
    'oauthScope': oauthScope,
  };

  factory McpServerConfig.fromJson(Map<String, Object?> json) =>
      McpServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        protocolVersion:
            json['protocolVersion'] as String? ??
            McpProtocolVersions.v2025_11_25,
        enabled: json['enabled'] as bool? ?? true,
        allowSessionMaterials: json['allowSessionMaterials'] as bool? ?? false,
        oauthClientId: json['oauthClientId'] as String?,
        oauthScope: json['oauthScope'] as String?,
        allowedTools: (json['allowedTools'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
      );
}

/// 一次工具发现的结果。
class McpToolInfo {
  const McpToolInfo({
    required this.name,
    required this.description,
    required this.readOnly,
    this.inputSchema = const {},
  });

  final String name;
  final String description;

  /// 服务器的 `annotations.readOnlyHint`。参考值，不是权限依据（§8.3）。
  final bool readOnly;

  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'readOnly': readOnly,
    'inputSchema': inputSchema,
  };

  factory McpToolInfo.fromJson(Map<String, Object?> json) => McpToolInfo(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    readOnly: json['readOnly'] as bool? ?? false,
    inputSchema: json['inputSchema'] is Map
        ? (json['inputSchema'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : const {},
  );
}

/// MCP 调用失败（网络、协议、权限、超时统一入口，message 供 UI 如实转述）。
class McpClientException implements Exception {
  const McpClientException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'McpClientException: $message${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// 远程 MCP 只读客户端（单服务器）。
class McpRemoteClient {
  McpRemoteClient({
    required this.config,
    required HttpClient http,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _http = http;

  final McpServerConfig config;
  final HttpClient _http;
  final Duration requestTimeout;

  int _nextId = 1;
  String? _sessionId;
  bool _initialized = false;
  String? _serverProtocolVersion;
  Map<String, String> _lastResponseHeaders = const {};

  bool get isConnected => _initialized;
  bool get _modern => config.protocolVersion == McpProtocolVersions.v2026_07_28;

  Map<String, String> _headers() => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    if (config.token?.isNotEmpty == true)
      'Authorization': 'Bearer ${config.token}',
    'MCP-Protocol-Version': ?_serverProtocolVersion,
    'Mcp-Session-Id': ?_sessionId,
  };

  Future<Map<String, Object?>> _rpc(
    String method, {
    Map<String, Object?>? params,
    bool notification = false,
    Map<String, String> extraHeaders = const {},
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled == true) throw HttpCanceledException();
    final id = notification ? null : _nextId++;
    final token = CancelToken();
    var finished = false;
    cancel?.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    try {
      final resp = await _http
          .post(
            config.url,
            headers: {
              ..._headers(),
              ...extraHeaders,
              if (_modern) 'MCP-Protocol-Version': config.protocolVersion,
              if (_modern) 'Mcp-Method': method,
              if (_modern && (params?['name'] ?? params?['uri']) != null)
                'Mcp-Name': encodeMcpHeader(
                  (params?['name'] ?? params?['uri']).toString(),
                ),
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': method,
              if (params != null || _modern)
                'params': {
                  ...?params,
                  if (_modern)
                    '_meta': {
                      'io.modelcontextprotocol/protocolVersion':
                          config.protocolVersion,
                      'io.modelcontextprotocol/clientInfo': {
                        'name': 'mianshi-zhilian-coach',
                        'version': '1.0',
                      },
                      'io.modelcontextprotocol/clientCapabilities':
                          <String, Object?>{},
                    },
                },
              if (!notification) 'id': id,
            }),
            cancel: token,
          )
          .timeout(
            requestTimeout,
            onTimeout: () {
              token.cancel();
              throw const McpClientException('MCP request timed out');
            },
          );
      if (token.isCancelled) throw HttpCanceledException();
      _lastResponseHeaders = resp.headers;
      if (resp.statusCode == 404 && _sessionId != null) close();
      if (!resp.isOk) {
        throw McpClientException(
          'MCP request failed: $method',
          statusCode: resp.statusCode,
        );
      }
      if (notification) return const {};
      if (resp.body.length > 256 * 1024) {
        throw const McpClientException(
          'MCP response exceeds the supported size',
        );
      }
      final payload = _parsePayload(resp.body, id!);
      if (payload.containsKey('error')) {
        // Remote error text can echo submitted credentials or personal material.
        throw McpClientException('MCP protocol error: $method');
      }
      return payload;
    } finally {
      finished = true;
    }
  }

  Map<String, Object?> _parsePayload(String raw, int requestId) {
    bool matches(Map<String, Object?> value) =>
        value['jsonrpc'] == '2.0' &&
        value['id'] == requestId &&
        (value.containsKey('result') != value.containsKey('error'));
    final text = raw.trim();
    if (text.startsWith('{')) {
      final value = _asMap(jsonDecode(text));
      if (matches(value)) return value;
    } else {
      // SSE data fields join per event, and notifications cannot replace the
      // matching RPC result even when they appear later in the stream.
      for (final event in text.split(RegExp(r'\r?\n\r?\n'))) {
        final data = event
            .split(RegExp(r'\r?\n'))
            .where((line) => line.startsWith('data:'))
            .map((line) => line.substring(5).replaceFirst(RegExp(r'^ '), ''))
            .join('\n');
        if (data.trim().isEmpty) continue;
        try {
          final value = _asMap(jsonDecode(data));
          if (matches(value)) return value;
        } on FormatException {
          continue;
        }
      }
    }
    throw const McpClientException('MCP response does not match the request');
  }

  Map<String, Object?> _asMap(Object? decoded) {
    if (decoded is! Map) {
      throw const McpClientException('MCP response is not an object');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 连接并完成协议握手。
  Future<void> connect({CancelToken? cancel}) async {
    close();
    if (!config.enabled ||
        !McpProtocolVersions.isSupported(config.protocolVersion)) {
      throw const McpClientException(
        'MCP configuration is disabled or unsupported',
      );
    }
    if (_modern) {
      // Modern requests are self-contained: no initialize, session or GET stream.
      await _rpc('tools/list', cancel: cancel);
      _initialized = true;
      return;
    }
    try {
      final resp = await _rpc(
        'initialize',
        params: {
          'protocolVersion': config.protocolVersion,
          'capabilities': const <String, Object?>{},
          'clientInfo': const {
            'name': 'mianshi-zhilian-coach',
            'version': '1.0',
          },
        },
        cancel: cancel,
      );
      final result = _asMap(resp['result']);
      final version = result['protocolVersion'];
      if (version is! String || !McpProtocolVersions.isSupported(version)) {
        throw const McpClientException(
          'MCP server negotiated an unsupported protocol',
        );
      }
      _serverProtocolVersion = version;
      _sessionId = _lastResponseHeaders['mcp-session-id'];
      await _rpc(
        'notifications/initialized',
        notification: true,
        cancel: cancel,
      );
      _initialized = true;
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// 工具发现。返回全部工具及只读注解，由上层决定放行哪些。
  Future<List<McpToolInfo>> listTools({CancelToken? cancel}) async {
    _requireConnected();
    final all = <McpToolInfo>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final resp = await _rpc(
        'tools/list',
        params: {'cursor': ?cursor},
        cancel: cancel,
      );
      final result = _asMap(resp['result']);
      final tools = result['tools'];
      if (tools is! List) {
        throw const McpClientException('MCP tools list missing');
      }
      all.addAll(
        tools.whereType<Map>().map((raw) {
          final t = raw.map((k, v) => MapEntry(k.toString(), v));
          final info = McpToolInfo.fromJson(t);
          final annotations = t['annotations'] is Map
              ? (t['annotations'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v),
                )
              : const <String, Object?>{};
          // 服务器未注解时视为“未知只读性”，按可写处理（宁可多拦，不可放行）。
          final hint = annotations['readOnlyHint'];
          final readOnly = hint is bool ? hint : false;
          return McpToolInfo(
            name: info.name,
            description: info.description,
            readOnly: readOnly,
            inputSchema: info.inputSchema,
          );
        }),
      );
      cursor = result['nextCursor'] as String?;
      if (cursor != null && (!cursors.add(cursor) || cursors.length > 100)) {
        throw const McpClientException('MCP pagination limit exceeded');
      }
    } while (cursor != null);
    if (_modern) {
      all.removeWhere((tool) {
        try {
          McpHeaderSchema(tool.inputSchema);
          return false;
        } on FormatException {
          return true;
        }
      });
    }
    return all;
  }

  /// 当前配置下允许调用的工具（必须由用户显式放行）。
  bool isToolAllowed(McpToolInfo tool) =>
      config.allowedTools.contains(tool.name);

  /// 调用一个已放行的只读工具，返回拼接后的文本内容。
  Future<String> callTool(
    String name,
    Map<String, Object?> arguments, {
    CancelToken? cancel,
  }) async {
    _requireConnected();
    final tools = await listTools(cancel: cancel);
    final target = tools.where((t) => t.name == name).firstOrNull;
    if (target == null) {
      throw McpClientException('MCP tool not found on server: $name');
    }
    if (!isToolAllowed(target)) {
      // 外部注解不可作权限依据：只有用户放行过的可写工具才可能被调用，
      // 首版只读边界下统一拒绝。
      throw McpClientException(
        'MCP tool is not read-only and was not explicitly allowed: $name',
      );
    }
    final resp = await _rpc(
      'tools/call',
      params: {'name': name, 'arguments': arguments},
      extraHeaders: _modern
          ? McpHeaderSchema(target.inputSchema).headers(arguments)
          : const {},
      cancel: cancel,
    );
    final result = _asMap(resp['result']);
    if (result['isError'] == true) {
      throw const McpClientException('MCP tool reported an error');
    }
    final content = result['content'];
    if (content is! List) return '';
    return content
        .whereType<Map>()
        .where((block) => block['type'] == 'text')
        .map((block) => block['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n');
  }

  void _requireConnected() {
    if (!_initialized) {
      throw const McpClientException('MCP client is not connected');
    }
  }

  /// 释放会话状态（HTTP 无长连接，仅清本地状态）。
  void close() {
    _sessionId = null;
    _initialized = false;
    _serverProtocolVersion = null;
    _lastResponseHeaders = const {};
  }
}
