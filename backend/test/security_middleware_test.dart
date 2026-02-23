import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../server/middleware/cors_policy_middleware.dart';
import '../server/middleware/rate_limit_middleware.dart';
import '../server/middleware/request_size_middleware.dart';
import '../server/middleware/security_headers_middleware.dart';
import '../server/middleware/trace_middleware.dart';

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

    test(
      'returns 429 envelope with non-empty trace_id in full pipeline',
      () async {
        final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);
        final handler = Pipeline()
            .addMiddleware(traceMiddleware())
            .addMiddleware(
              rateLimitMiddleware(
                window: const Duration(minutes: 1),
                maxRequestsPerIp: 1,
                maxRequestsPerUser: 1,
                nowProvider: () => fixedNow,
              ),
            )
            .addHandler((request) async => Response.ok('ok'));

        final first = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/rides/one'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.4'},
          ),
        );
        final second = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/rides/two'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.4'},
          ),
        );

        expect(first.statusCode, 200);
        expect(second.statusCode, 429);
        final body =
            jsonDecode(await second.readAsString()) as Map<String, dynamic>;
        expect(body['code'], 'rate_limited');
        final traceId = (body['trace_id'] as String?) ?? '';
        expect(traceId.isNotEmpty, isTrue);
        expect(traceId, isNot('trace-unset'));
      },
    );

    test('auth endpoints use stricter auth-specific thresholds', () async {
      final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);
      final handler = Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 10,
              maxRequestsPerUser: 10,
              maxAuthRequestsPerIp: 1,
              maxAuthRequestsPerUser: 1,
              nowProvider: () => fixedNow,
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final firstAuth = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/login'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.2'},
        ),
      );
      final secondAuth = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/login'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.2'},
        ),
      );
      final general = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/rides/one'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.3'},
        ),
      );

      expect(firstAuth.statusCode, 200);
      expect(secondAuth.statusCode, 429);
      expect(general.statusCode, 200);
    });

    test(
      'marketplace routes use dedicated read/write buckets and RATE_LIMITED envelope',
      () async {
        final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);
        final handler = Pipeline()
            .addMiddleware(
              rateLimitMiddleware(
                window: const Duration(minutes: 1),
                maxRequestsPerIp: 1,
                maxRequestsPerUser: 1,
                maxMarketplaceReadRequestsPerIp: 3,
                maxMarketplaceReadRequestsPerUser: 3,
                maxMarketplaceWriteRequestsPerIp: 1,
                maxMarketplaceWriteRequestsPerUser: 1,
                nowProvider: () => fixedNow,
              ),
            )
            .addHandler((request) async => Response.ok('ok'));

        final readOne = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/marketplace/offers'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.8'},
          ),
        );
        final readTwo = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/marketplace/offers'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.8'},
          ),
        );
        final writeOne = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/marketplace/purchases'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.8'},
          ),
        );
        final writeTwo = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/marketplace/purchases'),
            headers: const <String, String>{'x-forwarded-for': '10.0.0.8'},
          ),
        );

        expect(readOne.statusCode, 200);
        expect(readTwo.statusCode, 200);
        expect(writeOne.statusCode, 200);
        expect(writeTwo.statusCode, 429);

        final body =
            jsonDecode(await writeTwo.readAsString()) as Map<String, dynamic>;
        expect(body['error_code'], 'RATE_LIMITED');
        expect(body['code'], 'rate_limited');
      },
    );

    test('webhook routes use high burst bucket', () async {
      final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);
      final handler = Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 1,
              maxRequestsPerUser: 1,
              maxWebhookRequestsPerIp: 3,
              maxWebhookRequestsPerUser: 3,
              nowProvider: () => fixedNow,
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final first = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.9'},
        ),
      );
      final second = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.9'},
        ),
      );
      final third = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.9'},
        ),
      );
      final fourth = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{'x-forwarded-for': '10.0.0.9'},
        ),
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(third.statusCode, 200);
      expect(fourth.statusCode, 429);
    });

    test('trust proxy headers toggle controls X-Forwarded-For usage', () async {
      final fixedNow = DateTime.utc(2026, 2, 15, 12, 0, 0);

      final trustedHandler = Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 1,
              maxRequestsPerUser: 10,
              trustProxyHeaders: true,
              nowProvider: () => fixedNow,
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final trustedFirst = await trustedHandler(
        Request(
          'GET',
          Uri.parse('http://localhost/health/one'),
          headers: const <String, String>{'x-forwarded-for': '198.51.100.10'},
        ),
      );
      final trustedSecond = await trustedHandler(
        Request(
          'GET',
          Uri.parse('http://localhost/health/two'),
          headers: const <String, String>{'x-forwarded-for': '198.51.100.11'},
        ),
      );
      expect(trustedFirst.statusCode, 200);
      expect(trustedSecond.statusCode, 200);

      final untrustedHandler = Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 1,
              maxRequestsPerUser: 10,
              trustProxyHeaders: false,
              nowProvider: () => fixedNow,
            ),
          )
          .addHandler((request) async => Response.ok('ok'));

      final untrustedFirst = await untrustedHandler(
        Request(
          'GET',
          Uri.parse('http://localhost/health/one'),
          headers: const <String, String>{'x-forwarded-for': '198.51.100.10'},
        ),
      );
      final untrustedSecond = await untrustedHandler(
        Request(
          'GET',
          Uri.parse('http://localhost/health/two'),
          headers: const <String, String>{'x-forwarded-for': '198.51.100.11'},
        ),
      );
      expect(untrustedFirst.statusCode, 200);
      expect(untrustedSecond.statusCode, 429);
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
      expect(response.headers['referrer-policy'], 'no-referrer');
      expect(response.headers['x-permitted-cross-domain-policies'], 'none');
      expect(response.headers['permissions-policy'], isNotNull);
      expect(response.headers['content-security-policy'], isNotNull);
      expect(
        response.headers['strict-transport-security'],
        contains('max-age=31536000'),
      );
    });

    test('does not add HSTS when disabled', () async {
      final handler = Pipeline()
          .addMiddleware(
            securityHeadersMiddleware(enableStrictTransportSecurity: false),
          )
          .addHandler((request) async => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );

      expect(response.statusCode, 200);
      expect(response.headers['strict-transport-security'], isNull);
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['x-frame-options'], 'SAMEORIGIN');
      expect(response.headers['referrer-policy'], 'no-referrer');
    });
  });

  group('request size middleware', () {
    test('returns 413 for oversized request by content-length', () async {
      final handler = Pipeline()
          .addMiddleware(requestSizeMiddleware(maxBytes: 8))
          .addHandler((request) async => Response.ok('ok'));

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/rides/request'),
          body: '{"payload":"0123456789"}',
        ),
      );

      expect(response.statusCode, 413);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['code'], 'request_body_too_large');
      expect((body['trace_id'] as String?)?.isNotEmpty, isTrue);
    });
  });
}
