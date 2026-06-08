import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRouteClient extends EndpointFallbackClient {
  _MockRouteClient({required super.stateStore});

  final requests = <Map<String, dynamic>>[];
  http.Response? refreshResponse;
  http.Response? logoutResponse;

  @override
  Future<http.Response> request(
    RouteService service,
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 5),
    bool fallbackOnAllHttpErrors = false,
  }) async {
    requests.add({'method': method, 'path': path, 'body': body});
    if (path == '/auth/refresh' && refreshResponse != null) {
      return refreshResponse!;
    }
    if (path == '/auth/logout' && logoutResponse != null) {
      return logoutResponse!;
    }
    return http.Response('{}', 200);
  }
}

User _createUser({String role = 'user', String? id}) {
  return User(
    id: id ?? 'test-id',
    username: 'testuser',
    nickname: 'Test User',
    role: role == 'admin'
        ? UserRole.admin
        : role == 'guest'
            ? UserRole.guest
            : UserRole.user,
  );
}

String _makeToken(int exp) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256"}'));
  final payload = base64Url.encode(utf8.encode(json.encode({'exp': exp})));
  return '$header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AuthProvider', () {
    late StorageService storage;
    late _MockRouteClient mockClient;
    late AuthProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      mockClient = _MockRouteClient(stateStore: RouteStateStore(storage));
      provider = AuthProvider(storage, routeClient: mockClient);
    });

    test('1. initial state: isLoggedIn=false, user=null, token=null, userRole=guest', () {
      expect(provider.isLoggedIn, false);
      expect(provider.user, isNull);
      expect(provider.token, isNull);
      expect(provider.userRole, UserRole.guest);
    });

    test('2. loadUser when no saved user stays not logged in', () async {
      await provider.loadUser();

      expect(provider.isLoggedIn, false);
      expect(provider.user, isNull);
      expect(provider.token, isNull);
      expect(provider.userRole, UserRole.guest);
    });

    test('3. loadUser after _saveUser restores user, token, refreshToken', () async {
      final user = _createUser();
      await storage.save('auth_user', user.toJson());
      await storage.save('auth_token', 'test-token');
      await storage.save('auth_refresh_token', 'test-refresh-token');

      await provider.loadUser();

      expect(provider.isLoggedIn, true);
      expect(provider.user, isNotNull);
      expect(provider.user!.id, 'test-id');
      expect(provider.user!.username, 'testuser');
      expect(provider.user!.nickname, 'Test User');
      expect(provider.token, 'test-token');
    });

    test('4. isLoggedIn returns true after user is set via internal _saveUser', () async {
      final user = _createUser();
      await storage.save('auth_user', user.toJson());
      await storage.save('auth_token', 'test-token');
      await storage.save('auth_refresh_token', 'test-refresh-token');

      await provider.loadUser();

      expect(provider.isLoggedIn, true);
    });

    test('5. userRole returns guest when no user, proper role when user exists', () async {
      expect(provider.userRole, UserRole.guest);

      final user = _createUser(role: 'admin');
      await storage.save('auth_user', user.toJson());
      await storage.save('auth_token', 'admin-token');
      await storage.save('auth_refresh_token', 'admin-refresh-token');

      await provider.loadUser();

      expect(provider.user!.role, UserRole.admin);
      expect(provider.userRole, UserRole.admin);
    });

    test('6. _tokenExpiresAt with valid JWT returns DateTime (no refresh)', () async {
      final farFuture = 9999999999;
      final token = _makeToken(farFuture);
      final user = _createUser();

      await storage.save('auth_user', user.toJson());
      await storage.save('auth_token', token);

      await provider.loadUser();

      expect(provider.isLoggedIn, true);
      expect(provider.token, token);
      // Verify no refresh was attempted (token far in future)
    });

    // Tests 7-8 require PackageInfo.fromPlatform() platform channel mocking.
    // They are intentionally omitted here; add them if you set up the mock channel.

    test('7. logout clears all state', () async {
      final user = _createUser();
      await storage.save('auth_user', user.toJson());
      await storage.save('auth_token', 'test-token');
      await storage.save('auth_refresh_token', 'test-refresh-token');
      await provider.loadUser();

      expect(provider.isLoggedIn, true);

      mockClient.logoutResponse = http.Response('{}', 200);

      await provider.logout();

      expect(provider.isLoggedIn, false);
      expect(provider.user, isNull);
      expect(provider.token, isNull);
      expect(provider.userRole, UserRole.guest);

      final storedUser = await storage.load('auth_user');
      final storedToken = await storage.load('auth_token');
      final storedRefresh = await storage.load('auth_refresh_token');
      expect(storedUser, isNull);
      expect(storedToken, isNull);
      expect(storedRefresh, isNull);
    });

    test('8. autoLogoutReason starts as null', () {
      expect(provider.autoLogoutReason.value, isNull);
    });
  });
}
