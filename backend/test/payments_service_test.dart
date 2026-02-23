import 'dart:convert';

import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../modules/payments/manual_payment_provider.dart';
import '../modules/payments/payment_service.dart';
import '../modules/payments/paystack_payment_provider.dart';

void main() {
  group('PaymentService webhook handling', () {
    test(
      'deduplicates webhook events by provider + provider_event_id',
      () async {
        final service = PaymentService(provider: ManualPaymentProvider());
        final body = jsonEncode(<String, Object?>{
          'provider_event_id': 'evt-dup-1',
          'event_type': 'payment_succeeded',
        });

        final first = await service.handleWebhook(
          headers: const <String, String>{},
          rawBody: body,
        );
        expect(first.duplicate, isFalse);

        final second = await service.handleWebhook(
          headers: const <String, String>{},
          rawBody: body,
        );
        expect(second.duplicate, isTrue);
        expect(second.action, 'duplicate_ignored');
      },
    );

    test(
      'returns signature exception when provider signature is invalid',
      () async {
        final metrics = RequestMetrics();
        final logs = <String>[];
        final service = PaymentService(
          provider: PaystackPaymentProvider(secretKey: 'super-secret'),
          metrics: metrics,
          logSink: logs.add,
        );
        final body = jsonEncode(<String, Object?>{
          'event': 'charge.success',
          'data': <String, Object?>{
            'id': 'evt-1',
            'metadata': <String, Object?>{
              'purchase_id': '3f5720c3-fc3b-450d-9760-404f476fddf2',
            },
          },
        });

        await expectLater(
          service.handleWebhook(
            headers: const <String, String>{
              'x-paystack-signature': 'invalid-signature',
            },
            rawBody: body,
          ),
          throwsA(isA<PaymentWebhookSignatureException>()),
        );

        final snapshot = metrics.snapshot();
        final webhookEvents =
            snapshot['marketplace_webhook_events_total'] as Map<String, int>;
        expect(webhookEvents, isA<Map<String, int>>());
        expect(logs, isNotEmpty);
        final parsed = jsonDecode(logs.first) as Map<String, dynamic>;
        expect(parsed['component'], 'payment_webhook');
        expect(parsed['verified'], isFalse);
        expect(parsed['action'], 'signature_invalid');
      },
    );
  });
}
