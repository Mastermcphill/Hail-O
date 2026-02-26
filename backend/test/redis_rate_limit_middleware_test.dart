import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/redis_client.dart';
import '../server/middleware/rate_limit_middleware.dart';

void main() {
  test('redis-backed rate limits persist across handler restarts', () async {
    final now = DateTime.utc(2026, 2, 26, 12, 0, 0);
    final redisClient = InMemoryRedisClient(nowUtc: () => now);
    Handler buildHandler() {
      return Pipeline()
          .addMiddleware(
            rateLimitMiddleware(
              window: const Duration(minutes: 1),
              maxRequestsPerIp: 1,
              maxRequestsPerUser: 1,
              redisClient: redisClient,
              nowProvider: () => now,
            ),
          )
          .addHandler((_) async => Response.ok('ok'));
    }

    final firstHandler = buildHandler();
    final first = await firstHandler(
      Request(
        'GET',
        Uri.parse('http://localhost/rides/one'),
        headers: const <String, String>{'x-forwarded-for': '203.0.113.10'},
      ),
    );
    expect(first.statusCode, 200);

    final restartedHandler = buildHandler();
    final second = await restartedHandler(
      Request(
        'GET',
        Uri.parse('http://localhost/rides/two'),
        headers: const <String, String>{'x-forwarded-for': '203.0.113.10'},
      ),
    );
    expect(second.statusCode, 429);
    final body =
        jsonDecode(await second.readAsString()) as Map<String, dynamic>;
    expect(body['error_code'], 'RATE_LIMITED');
  });
}
