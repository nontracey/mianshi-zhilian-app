import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import '../coach/mcp/oauth.dart';
import '../coach/mcp/mcp_client.dart';
import 'storage_service.dart';

class McpOAuthService {
  McpOAuthService(this.storage, this.profileId);
  final StorageService storage;
  final String profileId;
  String _slot(McpServerConfig c) =>
      'mcp_oauth_${sha256.convert(utf8.encode(jsonEncode([profileId, c.id, c.url, c.oauthClientId])))}';
  Uri get redirectUri => kIsWeb
      ? Uri.base.resolve('mcp-auth.html')
      : [
          TargetPlatform.windows,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform)
      ? Uri.parse('http://localhost:43827/callback')
      : Uri.parse('mianshizhilian-mcp://oauth/callback');
  Future<T> _withClient<T>(Future<T> Function(McpOAuthClient) action) async {
    final transport = http.Client();
    try {
      return await action(
        McpOAuthClient(
          httpClient: transport,
          authorize: (url, redirect) async => Uri.parse(
            await FlutterWebAuth2.authenticate(
              url: url.toString(),
              callbackUrlScheme:
                  !kIsWeb &&
                      [
                        TargetPlatform.windows,
                        TargetPlatform.linux,
                      ].contains(defaultTargetPlatform)
                  ? redirect.toString()
                  : redirect.scheme,
              options: const FlutterWebAuth2Options(useWebview: false),
            ),
          ),
        ),
      );
    } finally {
      transport.close();
    }
  }

  Future<void> login(McpServerConfig config) async {
    final grant = await _withClient(
      (client) => client.login(
        resource: config.url,
        clientId: config.oauthClientId!,
        redirectUri: redirectUri,
        requestedScope: config.oauthScope ?? '',
      ),
    );
    if (!await storage.writeSecret(
      _slot(config),
      jsonEncode(grant.toSecretJson()),
    )) {
      throw const McpOAuthException('secure_storage_failed');
    }
  }

  Future<String?> token(McpServerConfig config) async {
    final raw = await storage.readSecret(_slot(config));
    if (raw == null || raw.isEmpty) return null;
    var grant = McpOAuthGrant.fromSecretJson(jsonDecode(raw));
    if (grant.resource != config.url || grant.clientId != config.oauthClientId) {
      throw const McpOAuthException('token_resource_mismatch');
    }
    if (grant.expiring && grant.refreshToken != null) {
      grant = await _withClient((client) => client.refresh(grant));
      if (!await storage.writeSecret(
        _slot(config),
        jsonEncode(grant.toSecretJson()),
      )) {
        throw const McpOAuthException('secure_storage_failed');
      }
    }
    if (grant.expiresAt != null && grant.expiresAt!.isBefore(DateTime.now())) {
      throw const McpOAuthException('login_required');
    }
    return grant.accessToken;
  }

  Future<void> delete(McpServerConfig config) =>
      storage.deleteSecret(_slot(config));
}
