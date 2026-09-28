/// Public-client OAuth authorization-code + S256 PKCE for remote MCP.
/// Discovery and tokens are resource bound. Browser UI and secure storage are
/// injected by the app; no credentials enter coach extension records.
library;

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class McpOAuthException implements Exception {
  const McpOAuthException(this.code);
  final String code;
  @override
  String toString() => 'MCP OAuth: $code';
}

class McpOAuthGrant {
  const McpOAuthGrant({
    required this.resource,
    required this.issuer,
    required this.tokenEndpoint,
    required this.clientId,
    required this.accessToken,
    required this.scope,
    this.refreshToken,
    this.expiresAt,
  });
  final String resource, issuer, tokenEndpoint, clientId, accessToken, scope;
  final String? refreshToken;
  final DateTime? expiresAt;
  bool get expiring =>
      expiresAt == null ||
      DateTime.now().add(const Duration(seconds: 60)).isAfter(expiresAt!);
  Map<String, Object?> toSecretJson() => {
    'resource': resource,
    'issuer': issuer,
    'tokenEndpoint': tokenEndpoint,
    'clientId': clientId,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'scope': scope,
    'expiresAt': expiresAt?.toIso8601String(),
  };
  factory McpOAuthGrant.fromSecretJson(Map<String, dynamic> j) => McpOAuthGrant(
    resource: j['resource'],
    issuer: j['issuer'],
    tokenEndpoint: j['tokenEndpoint'],
    clientId: j['clientId'],
    accessToken: j['access_token'],
    refreshToken: j['refresh_token'],
    scope: j['scope'],
    expiresAt: j['expiresAt'] == null ? null : DateTime.parse(j['expiresAt']),
  );
}

class McpOAuthClient {
  McpOAuthClient({required this.httpClient, required this.authorize});
  final http.Client httpClient;
  final Future<Uri> Function(Uri authorizationUrl, Uri redirectUri) authorize;
  String _random() => base64UrlEncode(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  Uri _https(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const McpOAuthException('insecure_endpoint');
    }
    return uri;
  }

  Future<http.Response> _request(Uri url, {Map<String, String>? body}) async {
    final request = http.Request(body == null ? 'GET' : 'POST', url)
      ..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (body != null) request.bodyFields = body;
    final response = await httpClient
        .send(request)
        .timeout(const Duration(seconds: 20));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const McpOAuthException('response_too_large');
      }
    }
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
    );
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode != 200) {
      throw const McpOAuthException('request_failed');
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const McpOAuthException('invalid_response');
    }
    return value;
  }

  Future<McpOAuthGrant> login({
    required String resource,
    required String clientId,
    required Uri redirectUri,
    String requestedScope = '',
  }) async {
    final target = _https(resource);
    if (clientId.trim().isEmpty) {
      throw const McpOAuthException('client_id_required');
    }
    final probe = await _request(target);
    final challenge = probe.headers['www-authenticate'] ?? '';
    String? challengeValue(String key) => RegExp(
      '$key="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(challenge)?.group(1);
    final advertised = challengeValue('resource_metadata');
    final locations = advertised != null
        ? [_https(advertised)]
        : [
            target.replace(
              path: '/.well-known/oauth-protected-resource${target.path}',
              query: '',
            ),
            target.replace(
              path: '/.well-known/oauth-protected-resource',
              query: '',
            ),
          ];
    Map<String, dynamic>? protected;
    for (final location in locations) {
      final response = await _request(location);
      if (response.statusCode == 404) continue;
      protected = _json(response);
      break;
    }
    if (protected == null || protected['resource'] != resource) {
      throw const McpOAuthException('resource_mismatch');
    }
    final issuers = protected['authorization_servers'];
    if (issuers is! List || issuers.isEmpty || issuers.first is! String) {
      throw const McpOAuthException('issuer_missing');
    }
    final issuer = issuers.first as String;
    final authority = _https(issuer);
    final suffix = authority.path == '/' ? '' : authority.path;
    final candidates = [
      authority.replace(
        path: '/.well-known/oauth-authorization-server$suffix',
        query: '',
      ),
      authority.replace(
        path: '/.well-known/openid-configuration$suffix',
        query: '',
      ),
      authority.replace(
        path: '$suffix/.well-known/openid-configuration',
        query: '',
      ),
    ];
    Map<String, dynamic>? metadata;
    for (final location in candidates) {
      final response = await _request(location);
      if (response.statusCode == 404) continue;
      metadata = _json(response);
      break;
    }
    if (metadata == null || metadata['issuer'] != issuer) {
      throw const McpOAuthException('issuer_mismatch');
    }
    if (!(metadata['code_challenge_methods_supported'] as List? ?? []).contains(
      'S256',
    )) {
      throw const McpOAuthException('pkce_s256_required');
    }
    final endpoint = _https(metadata['authorization_endpoint'] as String);
    final tokenEndpoint = _https(metadata['token_endpoint'] as String);
    final verifier = _random(), state = _random();
    final scope = requestedScope.trim().isNotEmpty
        ? requestedScope.trim()
        : challengeValue('scope') ??
              (protected['scopes_supported'] as List? ?? []).join(' ');
    final url = endpoint.replace(
      queryParameters: {
        ...endpoint.queryParameters,
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri.toString(),
        'resource': resource,
        if (scope.isNotEmpty) 'scope': scope,
        'state': state,
        'code_challenge': base64UrlEncode(
          sha256.convert(ascii.encode(verifier)).bytes,
        ).replaceAll('=', ''),
        'code_challenge_method': 'S256',
      },
    );
    final callback = await authorize(url, redirectUri);
    if (callback.replace(query: '', fragment: '') !=
            redirectUri.replace(query: '', fragment: '') ||
        callback.queryParametersAll.values.any((v) => v.length != 1) ||
        callback.queryParameters['state'] != state) {
      throw const McpOAuthException('callback_mismatch');
    }
    final responseIssuer = callback.queryParameters['iss'];
    if ((metadata['authorization_response_iss_parameter_supported'] == true &&
            responseIssuer == null) ||
        (responseIssuer != null && responseIssuer != issuer)) {
      throw const McpOAuthException('callback_issuer_mismatch');
    }
    if (callback.queryParameters.containsKey('error')) {
      throw const McpOAuthException('authorization_denied');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const McpOAuthException('code_missing');
    }
    final response = _json(
      await _request(
        tokenEndpoint,
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': verifier,
          'client_id': clientId,
          'redirect_uri': redirectUri.toString(),
          'resource': resource,
        },
      ),
    );
    return _grant(
      response,
      resource: resource,
      issuer: issuer,
      tokenEndpoint: tokenEndpoint.toString(),
      clientId: clientId,
      scope: scope,
    );
  }

  Future<McpOAuthGrant> refresh(McpOAuthGrant previous) async {
    if (previous.refreshToken == null) {
      throw const McpOAuthException('login_required');
    }
    final json = _json(
      await _request(
        _https(previous.tokenEndpoint),
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': previous.refreshToken!,
          'client_id': previous.clientId,
          'resource': previous.resource,
          if (previous.scope.isNotEmpty) 'scope': previous.scope,
        },
      ),
    );
    return _grant(
      json,
      resource: previous.resource,
      issuer: previous.issuer,
      tokenEndpoint: previous.tokenEndpoint,
      clientId: previous.clientId,
      scope: previous.scope,
      oldRefresh: previous.refreshToken,
    );
  }

  McpOAuthGrant _grant(
    Map json, {
    required String resource,
    required String issuer,
    required String tokenEndpoint,
    required String clientId,
    required String scope,
    String? oldRefresh,
  }) {
    if ((json['token_type'] as String? ?? '').toLowerCase() != 'bearer' ||
        json['access_token'] is! String ||
        (json['access_token'] as String).isEmpty) {
      throw const McpOAuthException('invalid_token');
    }
    final seconds = json['expires_in'];
    return McpOAuthGrant(
      resource: resource,
      issuer: issuer,
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'] as String? ?? oldRefresh,
      scope: json['scope'] as String? ?? scope,
      expiresAt: seconds is num
          ? DateTime.now().add(Duration(seconds: seconds.toInt()))
          : null,
    );
  }
}
