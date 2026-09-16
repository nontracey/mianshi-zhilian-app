/// MCP 扩展服务的配置装配（§8.2「设置页下的扩展服务」）。
///
/// 职责划分：
/// - 服务器**配置**（名称/地址/协议版本/放行工具）存教练库扩展记录
///   （`mcpConfigMetadata`），可随备份走；
/// - **凭证**（Bearer Token）只进系统安全存储，不进备份、不进设置 JSON；
/// - 连接测试在装配层完成，UI 只消费结果摘要，不接触协议细节。
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../coach/mcp/mcp_client.dart';
import '../coach/tools/remote_tools.dart';
import '../coach/model/messages.dart';
import '../coach/model/http_client.dart' show CancelToken;
import '../coach/persistence/coach_store.dart';
import '../coach/persistence/extension_records.dart';
import '../providers/coach_provider.dart' show kDefaultProfileId;
import 'coach_http_client.dart';
import 'storage_service.dart';
import 'mcp_oauth_service.dart';

/// 连接测试结果（协议值 + 计数，文案由 UI 翻译）。
class McpProbeSummary {
  const McpProbeSummary({
    required this.ok,
    this.toolCount = 0,
    this.readOnlyToolCount = 0,
    this.tools = const [],
    this.error,
  });

  final bool ok;
  final int toolCount;
  final int readOnlyToolCount;
  final List<McpToolInfo> tools;
  final String? error;
}

class McpConfigService extends ChangeNotifier {
  McpConfigService({
    required CoachStore store,
    required StorageService storage,
    this.profileId = kDefaultProfileId,
  }) : _store = store,
       _storage = storage;

  final CoachStore _store;
  final StorageService _storage;

  final String profileId;
  McpOAuthService get _oauth => McpOAuthService(_storage, profileId);
  Uri get oauthRedirectUri => _oauth.redirectUri;
  Future<void> authorize(McpServerConfig config) async {
    await _oauth.login(config);
    notifyListeners();
  }

  String _secretSlot(String serverId, String url) =>
      'mcp_token_${sha256.convert(utf8.encode(jsonEncode([profileId, serverId, url.trim()])))}';

  /// 全部已配置服务（token 已从安全存储合并，UI 不得展示）。
  Future<List<McpServerConfig>> list() async {
    final records = await _store.listExtensions(
      profileId,
      CoachExtensionKind.mcpConfigMetadata,
    );
    final configs = <McpServerConfig>[];
    for (final record in records) {
      try {
        final base = McpServerConfig.fromJson(record.value);
        String? token;
        if (base.oauthClientId?.isNotEmpty == true) {
          try {
            token = await _oauth.token(base);
          } catch (_) {
            token = null;
          }
        } else {
          token = await _storage.readSecret(_secretSlot(base.id, base.url));
        }
        configs.add(base.copyWith(token: token));
      } catch (e) {
        debugPrint('skip unparsable MCP config ${record.id}: $e');
      }
    }
    return configs;
  }

  /// 保存配置；[token] 为空字符串表示清除，null 表示不变。
  Future<bool> save(McpServerConfig config, {String? token}) async {
    if (token != null) {
      final ok = await _storage.writeSecret(
        _secretSlot(config.id, config.url),
        token,
      );
      if (!ok) return false;
    }
    final previous = await _store.getExtension(
      profileId,
      CoachExtensionKind.mcpConfigMetadata,
      config.id,
    );
    await _store.putExtension(
      CoachExtensionRecord(
        profileId: profileId,
        kind: CoachExtensionKind.mcpConfigMetadata,
        id: config.id,
        revision: (previous?.revision ?? 0) + 1,
        value: config.toJson(),
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return true;
  }

  Future<void> delete(String id) async {
    final record = await _store.getExtension(
      profileId,
      CoachExtensionKind.mcpConfigMetadata,
      id,
    );
    if (record == null) return;
    final config = McpServerConfig.fromJson(record.value);
    await _storage.deleteSecret(_secretSlot(id, config.url));
    await _oauth.delete(config);
    await _store.deleteExtension(
      profileId,
      CoachExtensionKind.mcpConfigMetadata,
      id,
    );
    notifyListeners();
  }

  Future<CoachRemoteTools> openCoachTools(CancelToken cancel) async {
    final http = CoachHttpClient();
    final clients = <McpRemoteClient>[];
    final entries = <String, ({McpRemoteClient client, McpToolInfo tool})>{};
    try {
      for (final config
          in (await list())
              .where(
                (c) =>
                    c.enabled &&
                    c.allowSessionMaterials &&
                    c.allowedTools.isNotEmpty,
              )
              .take(4)) {
        final client = McpRemoteClient(http: http, config: config);
        clients.add(client);
        await client.connect(cancel: cancel);
        for (final tool in (await client.listTools(
          cancel: cancel,
        )).where((t) => client.isToolAllowed(t)).take(12)) {
          final name =
              'mcp_${sha256.convert(utf8.encode('${config.id}:${tool.name}')).toString().substring(0, 24)}';
          entries[name] = (client: client, tool: tool);
        }
      }
      return CoachRemoteTools(
        specs: entries.entries
            .map(
              (e) => ToolSpec(
                name: e.key,
                description: e.value.tool.description.substring(
                  0,
                  e.value.tool.description.length.clamp(0, 1000),
                ),
                parameters: Map<String, dynamic>.from(e.value.tool.inputSchema),
              ),
            )
            .toList(),
        execute: (call, token) async {
          final entry = entries[call.name];
          if (entry == null) throw StateError('Tool has not been authorized');
          if (jsonEncode(call.arguments).length > 6000)
            throw StateError('Tool arguments too large');
          // Re-read grants before every call so revocation takes effect mid-turn.
          final configs = await list();
          if (!configs.any(
            (c) =>
                c.id == entry.client.config.id &&
                c.url == entry.client.config.url &&
                c.enabled &&
                c.allowSessionMaterials &&
                c.allowedTools.contains(entry.tool.name),
          )) {
            throw StateError('Tool authorization revoked');
          }
          final result = await entry.client.callTool(
            entry.tool.name,
            call.arguments,
            cancel: token,
          );
          return result.substring(0, result.length.clamp(0, 8000));
        },
        close: () {
          for (final client in clients) {
            client.close();
          }
          http.close();
        },
      );
    } catch (_) {
      for (final client in clients) {
        client.close();
      }
      http.close();
      rethrow;
    }
  }

  /// 连接测试：握手 → 工具发现 → 返回只读子集信息。
  Future<McpProbeSummary> testConnection(McpServerConfig config) async {
    final http = CoachHttpClient();
    final client = McpRemoteClient(http: http, config: config);
    try {
      await client.connect();
      final tools = await client.listTools();
      return McpProbeSummary(
        ok: true,
        toolCount: tools.length,
        readOnlyToolCount: tools.where((t) => t.readOnly).length,
        tools: tools,
      );
    } catch (e) {
      return McpProbeSummary(ok: false, error: e.toString());
    } finally {
      client.close();
      http.close();
    }
  }
}
