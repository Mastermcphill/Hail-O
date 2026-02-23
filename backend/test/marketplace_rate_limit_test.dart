import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/request_context.dart';
import '../server/middleware/rate_limit_middleware.dart';
import '../server/middleware/trace_middleware.dart';

void main() {
  test('marketplace write routes use dedicated stricter bucket', () async {
    final nowUtc = DateTime.utc(2026, 2, 22, 12, 0, 0);
    final handler = Pipeline()
        .addMiddleware(traceMiddleware())
        .addMiddleware(
          rateLimitMiddleware(
            window: const Duration(minutes: 1),
            maxRequestsPerIp: 100,
            maxRequestsPerUser: 100,
            maxMarketplaceReadRequestsPerIp: 100,
            maxMarketplaceReadRequestsPerUser: 100,
            maxMarketplaceWriteRequestsPerIp: 1,
            maxMarketplaceWriteRequestsPerUser: 1,
            nowProvider: () => nowUtc,
          ),
        )
        .addHandler((request) async => Response.ok('ok'));

    Request request() {
      final base = Request(
        'POST',
        Uri.parse('http://localhost/marketplace/purchases'),
        headers: const <String, String>{'x-forwarded-for': '203.0.113.10'},
      );
      return RequestContext.withContext(
        base,
        const RequestContext(
          traceId: 'trace-market-rate',
          userId: 'user-rate-1',
          role: 'rider',
        ),
      );
    }

    final first = await handler(request());
    final second = await handler(request());

    expect(first.statusCode, 200);
    expect(second.statusCode, 429);
    final body =
        jsonDecode(await second.readAsString()) as Map<String, dynamic>;
    expect(body['code'], 'rate_limited');
    expect((body['trace_id'] as String?)?.isNotEmpty, isTrue);
  });
}
