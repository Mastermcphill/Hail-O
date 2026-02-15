import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../server/middleware/cors_policy_middleware.dart';
import '../server/middleware/rate_limit_middleware.dart';
import '../server/middleware/security_headers_middleware.dart';

void main() {
  group('rate limit middleware', () {
    test('returns 429 when per-IP limit is exceeded', () async {
      final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);
      final handler = Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 2,
              maxRequestsPerUser: 2,
              nowProvider: () => fixedNow,
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final first = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/rides/one'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.1'},
        ),
      );
      final second = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/rides/two'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.1'},
        ),
      );
      final third = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/rides/three'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.1'},
        ),
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(third.statusCode, 429);
      final body =
          jsonDecode(await third.readAsString()) as Map<String, dynamic>;
      expect(body['code'], 'rate_limited');
    });
  });

  group('cors policy middleware', () {
    test('allows configured origin and denies unknown origin', () async {
      final handler = Pipeline()
          .addMiddleware(
            corsPolicyMiddleware(
              allowedOrigins: const <String>{'https://app.hailo.test'},
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final allowed = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/health'),
          headers: const <String, String>{'origin': 'https://app.hailo.test'},
        ),
      );
      final denied = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/health'),
          headers: const <String, String>{'origin': 'https://evil.example'},
        ),
      );

      expect(allowed.statusCode, 200);
      expect(
        allowed.headers['access-control-allow-origin'],
        'https://app.hailo.test',
      );
      expect(denied.statusCode, 403);
      final body =
          jsonDecode(await denied.readAsString()) as Map<String, dynamic>;
      expect(body['code'], 'cors_origin_denied');
    });
  });

  group('security headers middleware', () {
    test('adds hardened headers and HSTS when enabled', () async {
      final handler = Pipeline()
          .addMiddleware(
            securityHeadersMiddleware(enableStrictTransportSecurity: true),
          )
          .addHandler((request) async => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );

      expect(response.statusCode, 200);
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['x-frame-options'], 'SAMEORIGIN');
      expect(response.headers['x-xss-protection'], '1; mode=block');
      expect(
        response.headers['strict-transport-security'],
        contains('max-age=31536000'),
      );
    });
  });
}
