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

    test('POST without caller idempotency does not retry on timeout', () async {
      var calls = 0;
      final storage = _InMemoryTokenStorage();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          calls += 1;
          if (request.url.path == '/auth/login') {
            throw TimeoutException('login timeout');
          }
          return http.Response('{}', 404);
        }),
      );

      await expectLater(
        () => apiClient.post(
          '/auth/login',
          body: <String, Object?>{
            'email': 'user@example.com',
            'password': 'pw',
          },
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'request_timeout',
          ),
        ),
      );

      expect(calls, 1);
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
  }
}
