import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mianshi_zhilian/coach/mcp/oauth.dart';

void main() {
  const resource = 'https://mcp.example/tools';
  const issuer = 'https://auth.example/tenant';
  final redirect = Uri.parse('mianshizhilian-mcp://oauth/callback');
  late List<http.Request> requests;
  late Map<String, String> parameters;
  late bool wrongState, wrongIssuer, wrongResource, redirectToken, omitIssuer;
  late McpOAuthClient client;
  setUp(() {
    requests = [];
    parameters = {};
    wrongState = wrongIssuer = wrongResource = redirectToken = omitIssuer =
        false;
    final transport = MockClient((request) async {
      requests.add(request);
      expect(
        request.headers.containsKey('authorization'),
        isFalse,
        reason: 'Discovery never receives a model key or existing bearer',
      );
      if (request.url.toString() == resource)
        return http.Response(
          '',
          401,
          headers: {
            'www-authenticate':
                'Bearer resource_metadata="https://mcp.example/metadata", scope="notes:read"',
          },
        );
      if (request.url.path == '/metadata')
        return http.Response(
          jsonEncode({
            'resource': wrongResource ? 'https://other.example' : resource,
            'authorization_servers': [issuer],
          }),
          200,
        );
      if (request.url.path == '/.well-known/oauth-authorization-server/tenant')
        return http.Response(
          jsonEncode({
            'issuer': issuer,
            'authorization_endpoint': '$issuer/authorize',
            'token_endpoint': '$issuer/token',
            'code_challenge_methods_supported': ['S256'],
            'authorization_response_iss_parameter_supported': true,
          }),
          200,
        );
      expect(request.url.toString(), '$issuer/token');
      if (redirectToken)
        return http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/tokens'},
        );
      final form = request.bodyFields;
      expect(form['resource'], resource);
      expect(form['client_id'], 'registered-client');
      if (form['grant_type'] == 'authorization_code') {
        expect(form['code_verifier']!.length, greaterThanOrEqualTo(43));
        expect(form['code_verifier'], isNot(parameters['code_challenge']));
      } else {
        expect(form['refresh_token'], 'refresh-one');
      }
      return http.Response(
        jsonEncode({
          'token_type': 'Bearer',
          'access_token': 'access-one',
          'refresh_token': 'refresh-one',
          'expires_in': 3600,
          'scope': 'notes:read',
        }),
        200,
      );
    });
    addTearDown(transport.close);
    client = McpOAuthClient(
      httpClient: transport,
      authorize: (url, callback) async {
        parameters = url.queryParameters;
        expect(parameters['resource'], resource);
        expect(parameters['code_challenge_method'], 'S256');
        expect(parameters['scope'], 'notes:read');
        return callback.replace(
          queryParameters: {
            'code': 'authorization-code',
            'state': wrongState ? 'wrong' : parameters['state']!,
            if (!omitIssuer)
              'iss': wrongIssuer ? 'https://evil.example' : issuer,
          },
        );
      },
    );
  });
  Future<McpOAuthGrant> login() => client.login(
    resource: resource,
    clientId: 'registered-client',
    redirectUri: redirect,
  );
  test(
    'resource discovery, PKCE, issuer validation and refresh preserve resource and scope',
    () async {
      final grant = await login();
      expect(grant.accessToken, 'access-one');
      expect(grant.resource, resource);
      expect(grant.scope, 'notes:read');
      final refreshed = await client.refresh(grant);
      expect(refreshed.refreshToken, 'refresh-one');
      expect(
        requests.where((r) => r.url.path.endsWith('/token')),
        hasLength(2),
      );
    },
  );
  test('forged callback state is rejected before code exchange', () async {
    wrongState = true;
    await expectLater(login(), throwsA(isA<McpOAuthException>()));
    expect(requests.where((r) => r.url.path.endsWith('/token')), isEmpty);
  });
  test(
    'wrong or required missing issuer never receives authorization code',
    () async {
      wrongIssuer = true;
      await expectLater(login(), throwsA(isA<McpOAuthException>()));
      wrongIssuer = false;
      omitIssuer = true;
      await expectLater(login(), throwsA(isA<McpOAuthException>()));
      expect(requests.where((r) => r.url.path.endsWith('/token')), isEmpty);
    },
  );
  test(
    'resource metadata cannot substitute a different protected service',
    () async {
      wrongResource = true;
      await expectLater(login(), throwsA(isA<McpOAuthException>()));
      expect(parameters, isEmpty);
    },
  );
  test(
    'token endpoint redirect is rejected without forwarding secrets',
    () async {
      redirectToken = true;
      await expectLater(login(), throwsA(isA<McpOAuthException>()));
      expect(requests.any((r) => r.url.host == 'evil.example'), isFalse);
    },
  );
}
