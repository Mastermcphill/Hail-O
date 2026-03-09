import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/api/api_errors.dart';
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

    test(
      'password login clears prior OTP refresh token and blocks stale refresh reuse',
      () async {
        final storage = InMemoryTokenStorage();
        var refreshCalls = 0;
        final apiClient = ApiClient(
          tokenStorage: storage,
          httpClient: MockClient((request) async {
            if (request.url.path == '/auth/otp/verify') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'ok': true,
                  'access_token': 'otp-access-token-a',
                  'refresh_token': 'otp-refresh-token-a',
                  'user': <String, Object?>{'role': 'rider'},
                }),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/auth/login') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'ok': true,
                  'token': 'password-login-token-b',
                  'role': 'driver',
                }),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/auth/token/refresh') {
              refreshCalls += 1;
              return http.Response(
                jsonEncode(<String, Object?>{
                  'ok': true,
                  'access_token': 'unexpected-refresh-token',
                }),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/protected') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'ok': false,
                  'code': 'unauthorized',
                  'message': 'expired',
                }),
                401,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.Response('{}', 404);
          }),
        );
        final session = AuthSession(
          tokenStorage: storage,
          apiClient: apiClient,
        );

        await session.verifyOtp(phoneE164: '+15550000001', code: '123456');
        expect(await storage.readRefreshToken(), 'otp-refresh-token-a');

        await session.login('account-b@example.com', 'password123');

        expect(session.roleNormalized, 'driver');
        expect(await storage.readToken(), 'password-login-token-b');
        expect(await storage.readRefreshToken(), isNull);

        await expectLater(
          () => apiClient.get('/protected'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        expect(refreshCalls, 0);
      },
    );

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
      await storage.saveAuth(
        token: 'active-token',
        role: 'driver',
        refreshToken: 'refresh-token',
      );
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
      expect(await storage.readRefreshToken(), isNull);
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
    _values.remove('refresh_token');
  }

  @override
  Future<void> saveAuth({
    required String token,
    required String role,
    String? refreshToken,
  }) async {
    await saveToken(token);
    await saveRole(role);
    final normalizedRefreshToken = (refreshToken ?? '').trim();
    if (normalizedRefreshToken.isNotEmpty) {
      await saveRefreshToken(normalizedRefreshToken);
    } else {
      await deleteRefreshToken();
    }
  }

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    _values['refresh_token'] = refreshToken;
  }

  @override
  Future<String?> readRefreshToken() async {
    return _values['refresh_token'];
  }

  @override
  Future<void> deleteRefreshToken() async {
    _values.remove('refresh_token');
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
