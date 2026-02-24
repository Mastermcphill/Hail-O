import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/auth/session/auth_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuthSession', () {
    test('init loads persisted token and role', () async {
      final storage = InMemoryTokenStorage();
      final persistedToken = JWT(<String, Object?>{
        'user_id': 'admin-1',
        'role': 'admin',
      }).sign(SecretKey('test-secret'), expiresIn: const Duration(hours: 1));
      await storage.saveAuth(token: persistedToken, role: 'admin');
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);

      await session.init();

      expect(session.isReady, isTrue);
      expect(session.isAuthenticated, isTrue);
      expect(session.token, persistedToken);
      expect(session.roleNormalized, 'admin');
    });

    test('login stores session and authenticates', () async {
      final storage = InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'token': 'login-token',
                'role': 'rider',
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);

      final result = await session.login('user@example.com', 'password123');

      expect(result.token, 'login-token');
      expect(session.isAuthenticated, isTrue);
      expect(session.roleNormalized, 'rider');
      expect(await storage.readToken(), 'login-token');
      expect(await storage.readRole(), 'rider');
    });

    test('requireAdmin prevents non-admin login state mutation', () async {
      final storage = InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'token': 'user-token',
                'role': 'rider',
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);

      expect(
        () => session.login(
          'user@example.com',
          'password123',
          requireAdmin: true,
        ),
        throwsA(isA<AuthSessionException>()),
      );
      expect(session.isAuthenticated, isFalse);
      expect(await storage.readToken(), isNull);
      expect(await storage.readRole(), isNull);
    });

    test('logout clears session state and storage', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveAuth(token: 'active-token', role: 'driver');
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);
      await session.init();

      await session.logout();

      expect(session.isAuthenticated, isFalse);
      expect(session.status, AuthStatus.anonymous);
      expect(session.token, isNull);
      expect(await storage.readToken(), isNull);
      expect(await storage.readRole(), isNull);
    });

    test('init clears expired token and role', () async {
      final expired = JWT(
        <String, Object?>{'user_id': 'user-1', 'role': 'rider'},
      ).sign(SecretKey('test-secret'), expiresIn: const Duration(seconds: -30));
      final storage = InMemoryTokenStorage();
      await storage.saveAuth(token: expired, role: 'rider');
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);

      await session.init();

      expect(session.isAuthenticated, isFalse);
      expect(session.status, AuthStatus.anonymous);
      expect(await storage.readToken(), isNull);
      expect(await storage.readRole(), isNull);
    });

    test('init clears malformed persisted token', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveAuth(token: 'not-a-jwt', role: 'admin');
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final session = AuthSession(tokenStorage: storage, apiClient: apiClient);

      await session.init();

      expect(session.isAuthenticated, isFalse);
      expect(session.status, AuthStatus.anonymous);
      expect(await storage.readToken(), isNull);
      expect(await storage.readRole(), isNull);
    });
  });
}

class InMemoryTokenStorage extends TokenStorage {
  InMemoryTokenStorage();

  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> saveToken(String token) async {
    _values['token'] = token;
  }

  @override
  Future<String?> readToken() async {
    return _values['token'];
  }

  @override
  Future<void> deleteToken() async {
    _values.remove('token');
  }

  @override
  Future<void> saveRole(String role) async {
    _values['role'] = role;
  }

  @override
  Future<String?> readRole() async {
    return _values['role'];
  }

  @override
  Future<void> deleteRole() async {
    _values.remove('role');
  }

  @override
  Future<void> clearAuth() async {
    _values.remove('token');
    _values.remove('role');
  }

  @override
  Future<void> saveAuth({required String token, required String role}) async {
    await saveToken(token);
    await saveRole(role);
  }

  @override
  Future<void> writeValue(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readValue(String key) async {
    return _values[key];
  }

  @override
  Future<void> deleteValue(String key) async {
    _values.remove(key);
  }
}
