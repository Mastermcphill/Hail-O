import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/api/api_errors.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient policy', () {
    test('GET retries once on timeout', () async {
      var calls = 0;
      final storage = _InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          calls += 1;
          if (request.url.path == '/health') {
            if (calls == 1) {
              throw TimeoutException('first timeout');
            }
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final response = await apiClient.get('/health');

      expect(calls, 2);
      expect(response['ok'], isTrue);
    });

    test('POST retries with generated idempotency key on timeout', () async {
      var calls = 0;
      final storage = _InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          calls += 1;
          if (request.url.path == '/auth/login') {
            if (calls < 3) {
              throw TimeoutException('login timeout');
            }
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final result = await apiClient.post(
        '/auth/login',
        body: <String, Object?>{'email': 'user@example.com', 'password': 'pw'},
      );

      expect(calls, 3);
      expect(result['ok'], isTrue);
    });

    test('401 triggers refresh once then retries request', () async {
      var protectedCalls = 0;
      var refreshCalls = 0;
      final storage = _InMemoryTokenStorage();
      await storage.saveToken('expired-token');
      await storage.saveRefreshToken('refresh-token');

      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path == '/protected') {
            protectedCalls += 1;
            final auth = request.headers['authorization'] ?? '';
            if (auth == 'Bearer expired-token') {
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
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true, 'value': 'done'}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/auth/token/refresh') {
            refreshCalls += 1;
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': true,
                'access_token': 'fresh-token',
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final response = await apiClient.get('/protected');

      expect(response['value'], 'done');
      expect(await storage.readToken(), 'fresh-token');
      expect(refreshCalls, 1);
      expect(protectedCalls, 2);
    });

    test('refresh failure clears auth and notifies logout hook', () async {
      final storage = _InMemoryTokenStorage();
      await storage.saveToken('expired-token');
      await storage.saveRefreshToken('refresh-token');
      var logoutCalls = 0;

      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
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
          if (request.url.path == '/auth/token/refresh') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': false,
                'code': 'unauthorized',
                'message': 'invalid refresh',
              }),
              401,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );
      apiClient.setAuthFailureHandler(() async {
        logoutCalls += 1;
      });

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

      expect(logoutCalls, 1);
      expect(await storage.readToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    });

    test('circuit breaker opens after repeated server failures', () async {
      var calls = 0;
      final storage = _InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          calls += 1;
          if (request.url.path == '/unstable') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'ok': false,
                'error_code': 'SERVER_BUSY',
                'message': 'busy',
              }),
              503,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      for (var i = 0; i < 4; i++) {
        await expectLater(
          () => apiClient.get('/unstable'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              503,
            ),
          ),
        );
      }

      final callsBeforeShortCircuit = calls;
      await expectLater(
        () => apiClient.get('/unstable'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'service_temporarily_unavailable',
          ),
        ),
      );

      expect(calls, callsBeforeShortCircuit);
    });
  });
}

class _InMemoryTokenStorage extends TokenStorage {
  _InMemoryTokenStorage();

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readToken() async {
    return _values['token'];
  }

  @override
  Future<String?> readRole() async {
    return _values['role'];
  }

  @override
  Future<void> saveToken(String token) async {
    _values['token'] = token;
  }

  @override
  Future<void> saveRole(String role) async {
    _values['role'] = role;
  }

  @override
  Future<void> deleteToken() async {
    _values.remove('token');
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
}
