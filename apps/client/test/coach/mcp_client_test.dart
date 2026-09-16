import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mianshi_zhilian/coach/mcp/mcp_client.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/services/coach_http_client.dart';

void main() {
  const endpoint = 'https://mcp.example.test/rpc';
  const version = McpProtocolVersions.v2025_11_25;
  late List<Map<String, dynamic>> requests;
  late CoachHttpClient transport;
  late McpRemoteClient client;
  late bool failNotification;
  late bool wrongId;
  late bool sse;
  late bool paginate;
  late bool cycle;

  setUp(() {
    requests = [];
    failNotification = wrongId = sse = paginate = cycle = false;
    transport = CoachHttpClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        Object result;
        if (body['method'] == 'initialize') {
          expect(request.headers.containsKey('Mcp-Session-Id'), isFalse);
          result = {
            'protocolVersion': version,
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'synthetic', 'version': '1'},
          };
        } else {
          // Exercise the production HTTP adapter, not just an abstract fake.
          expect(request.headers['Mcp-Session-Id'], 'session-42');
          expect(request.headers['MCP-Protocol-Version'], version);
          if (body['method'] == 'notifications/initialized') {
            expect(body.containsKey('id'), isFalse);
            return http.Response('', failNotification ? 401 : 202);
          }
          if (body['method'] == 'tools/list') {
            final next = (body['params'] as Map)['cursor'];
            result = {
              'tools': [
                {
                  'name': next == null ? 'read_note' : 'read_more',
                  'annotations': {'readOnlyHint': true},
                },
                {
                  'name': 'delete_file',
                  'annotations': {'readOnlyHint': true},
                },
              ],
              if (paginate && (next == null || cycle)) 'nextCursor': 'page-2',
            };
          } else {
            expect(body['method'], 'tools/call');
            expect((body['params'] as Map)['name'], 'read_note');
            result = {
              'content': [
                {'type': 'text', 'text': 'saved note'},
              ],
            };
          }
        }
        final payload = {
          'jsonrpc': '2.0',
          'id': wrongId ? 999 : body['id'],
          'result': result,
        };
        final json = jsonEncode(payload);
        return http.Response(
          sse
              ? 'data: ${json.substring(0, json.indexOf(',') + 1)}\r\n'
                    'data: ${json.substring(json.indexOf(',') + 1)}\r\n\r\n'
                    'data: {"jsonrpc":"2.0","method":"notifications/progress"}\r\n\r\n'
              : json,
          200,
          headers: {'Mcp-Session-Id': 'session-42'},
        );
      }),
    );
    client = McpRemoteClient(
      config: const McpServerConfig(
        id: 'm1',
        name: 'synthetic',
        url: endpoint,
        allowedTools: ['read_note'],
      ),
      http: transport,
    );
  });
  tearDown(() {
    client.close();
    transport.close();
  });

  test(
    'real HTTP adapter preserves session headers and initialized notification',
    () async {
      await client.connect();
      expect(client.isConnected, isTrue);
      expect(await client.listTools(), hasLength(2));
      expect(await client.callTool('read_note', {}), 'saved note');
    },
  );
  test('server readOnlyHint cannot grant itself permission', () async {
    await client.connect();
    await expectLater(
      client.callTool('delete_file', {}),
      throwsA(isA<McpClientException>()),
    );
    expect(requests.where((r) => r['method'] == 'tools/call'), isEmpty);
  });
  test('failed initialized notification never reports connected', () async {
    failNotification = true;
    await expectLater(client.connect(), throwsA(isA<McpClientException>()));
    expect(client.isConnected, isFalse);
  });
  test('wrong JSON-RPC response id is rejected', () async {
    wrongId = true;
    await expectLater(client.connect(), throwsA(isA<McpClientException>()));
  });
  test(
    'multiline SSE response matches id and ignores trailing notifications',
    () async {
      sse = true;
      await client.connect();
      expect(await client.listTools(), hasLength(2));
    },
  );
  test(
    'tool discovery follows pagination and rejects repeated cursors',
    () async {
      paginate = true;
      await client.connect();
      expect(
        (await client.listTools()).map((t) => t.name),
        contains('read_more'),
      );
      cycle = true;
      await expectLater(client.listTools(), throwsA(isA<McpClientException>()));
    },
  );
  test('cancellation before connect sends no request', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      client.connect(cancel: token),
      throwsA(isA<HttpCanceledException>()),
    );
    expect(requests, isEmpty);
  });
  test('unsupported protocol and disabled config send no requests', () async {
    for (final config in [
      const McpServerConfig(
        id: 'm2',
        name: 'future',
        url: endpoint,
        protocolVersion: '2099-01-01',
      ),
      const McpServerConfig(
        id: 'm2',
        name: 'disabled',
        url: endpoint,
        enabled: false,
      ),
    ]) {
      await expectLater(
        McpRemoteClient(config: config, http: transport).connect(),
        throwsA(isA<McpClientException>()),
      );
    }
    expect(requests, isEmpty);
  });
  test('config serialization excludes credentials', () {
    const config = McpServerConfig(
      id: 'm1',
      name: 'synthetic',
      url: endpoint,
      token: 'secret-token',
    );
    expect(jsonEncode(config.toJson()), isNot(contains('secret-token')));
  });
}
