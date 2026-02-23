import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/request_context.dart';
import '../infra/request_metrics.dart';
import '../server/middleware/observability_middleware.dart';

void main() {
  test(
    'observability middleware emits structured marketplace log fields',
    () async {
      final metrics = RequestMetrics();
      final logs = <String>[];
      final handler = Pipeline()
          .addMiddleware(
            observabilityMiddleware(metrics: metrics, logSink: logs.add),
          )
          .addHandler(
            (request) async => Response(
              200,
              headers: const <String, String>{
                'x-marketplace-purchase-id':
                    '3f5720c3-fc3b-450d-9760-404f476fddf2',
              },
              body: 'ok',
            ),
          );

      final request = RequestContext.withContext(
        Request('POST', Uri.parse('http://localhost/marketplace/purchases')),
        const RequestContext(
          traceId: 'trace-observe-1',
          userId: 'user-123',
          idempotencyKey: 'idem-abc',
        ),
      );
      final response = await handler(request);
      expect(response.statusCode, 200);

      expect(logs.length, 1);
      final logged = jsonDecode(logs.first) as Map<String, dynamic>;
      expect(logged['trace_id'], 'trace-observe-1');
      expect(logged['route'], 'marketplace/purchases');
      expect(logged['method'], 'POST');
      expect(logged['status_code'], 200);
      expect(logged.containsKey('latency_ms'), isTrue);
      expect(logged['user_id'], 'user-123');
      expect(logged['purchase_id'], '3f5720c3-fc3b-450d-9760-404f476fddf2');
      expect((logged['idempotency_key'] as String?)?.isNotEmpty, isTrue);
    },
  );

  test('metrics snapshot exposes marketplace counters and latency maps', () {
    final metrics = RequestMetrics();
    metrics.recordRequest(
      statusCode: 200,
      method: 'GET',
      path: 'marketplace/offers',
      latencyMs: 18,
    );
    metrics.recordRequest(
      statusCode: 200,
      method: 'POST',
      path: 'marketplace/purchases',
      latencyMs: 27,
    );
    metrics.recordMarketplaceWebhookEvent(
      provider: 'manual',
      action: 'payment_succeeded',
    );
    metrics.recordMarketplaceDbQueryLatency(
      op: 'insert_webhook_event',
      latencyMs: 12,
    );

    final snapshot = metrics.snapshot();
    expect(snapshot['marketplace_requests_total'], isA<Map<String, int>>());
    expect(
      (snapshot['marketplace_purchase_creates_total']
          as Map<String, int>)['success'],
      1,
    );
    expect(
      snapshot['marketplace_webhook_events_total'],
      isA<Map<String, int>>(),
    );
    expect(
      snapshot['marketplace_handler_latency_ms'],
      isA<Map<String, Object?>>(),
    );
    expect(
      snapshot['marketplace_db_query_latency_ms'],
      isA<Map<String, Object?>>(),
    );
    expect(snapshot['marketplace_alert_signals'], isA<Map<String, int>>());
  });
}
