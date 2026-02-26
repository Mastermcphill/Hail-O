import 'dart:convert';

import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/in_memory_marketplace_offer_repository.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/payments/manual_payment_provider.dart';
import '../modules/payments/payment_intent_repository.dart';
import '../modules/payments/payment_service.dart';
import '../modules/payments/payment_provider.dart';
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

    test(
      'duplicate payment_succeeded does not double-apply escrow transitions',
      () async {
        final offerRepository = InMemoryMarketplaceOfferRepository();
        final intentRepository = InMemoryPaymentIntentRepository();
        final ledgerRepository = InMemoryBillingLedgerRepository();
        final service = PaymentService(
          provider: ManualPaymentProvider(),
          offerRepository: offerRepository,
          paymentIntentRepository: intentRepository,
          billingLedgerRepository: ledgerRepository,
        );

        final purchase = await offerRepository.createOrGetPurchase(
          userId: 'webhook-user-1',
          offerId: 'offer_sedan_01',
          seatCount: 1,
          idempotencyKey: 'webhook-idem-1',
          provider: 'paystack',
        );
        final intent = await service.createPaymentIntent(
          userId: purchase.userId,
          purchaseId: purchase.id,
        );

        final body = jsonEncode(<String, Object?>{
          'provider_event_id': 'evt-escrow-1',
          'event_type': 'payment_succeeded',
          'purchase_id': purchase.id,
          'amount_minor': purchase.totalAmountMinor,
          'currency': purchase.currency,
        });
        final first = await service.handleWebhook(
          headers: const <String, String>{},
          rawBody: body,
        );
        final second = await service.handleWebhook(
          headers: const <String, String>{},
          rawBody: body,
        );
        expect(first.duplicate, isFalse);
        expect(second.duplicate, isTrue);

        final updatedIntent = await service.getPaymentIntentForUser(
          userId: purchase.userId,
          intentId: intent.id,
        );
        expect(updatedIntent, isNotNull);
        expect(updatedIntent!.status, 'succeeded');

        final ledger = await ledgerRepository.listByPurchase(
          purchaseId: purchase.id,
        );
        final debitEntries = ledger
            .where(
              (entry) => entry.metadata['ledger_leg'] == 'user_escrow_debit',
            )
            .toList(growable: false);
        final creditEntries = ledger
            .where(
              (entry) =>
                  entry.metadata['ledger_leg'] == 'platform_escrow_credit',
            )
            .toList(growable: false);
        expect(debitEntries.length, 1);
        expect(creditEntries.length, 1);
      },
    );

    test(
      'createPaymentIntent persists provider_ref from checkout provider',
      () async {
        final offerRepository = InMemoryMarketplaceOfferRepository();
        final intentRepository = InMemoryPaymentIntentRepository();
        final service = PaymentService(
          provider: _CheckoutStubProvider(
            checkout: const PaymentCheckoutResult(
              provider: 'paystack',
              status: 'PENDING',
              providerPaymentIntentId: 'pst_ref_custom',
              raw: <String, Object?>{
                'authorization_url':
                    'https://checkout.paystack.com/pst_ref_custom',
              },
            ),
          ),
          offerRepository: offerRepository,
          paymentIntentRepository: intentRepository,
        );

        final purchase = await offerRepository.createOrGetPurchase(
          userId: 'intent-provider-ref-user-1',
          offerId: 'offer_sedan_01',
          seatCount: 1,
          idempotencyKey: 'intent-provider-ref-idem-1',
          provider: 'paystack',
        );
        final intent = await service.createPaymentIntent(
          userId: purchase.userId,
          purchaseId: purchase.id,
        );

        expect(intent.provider, 'paystack');
        expect(intent.providerRef, 'pst_ref_custom');
        expect(
          intent.clientSecret,
          'https://checkout.paystack.com/pst_ref_custom',
        );
        expect(intent.status, 'pending');
      },
    );
  });
}

class _CheckoutStubProvider implements PaymentProvider {
  const _CheckoutStubProvider({required this.checkout});

  final PaymentCheckoutResult checkout;

  @override
  String get provider => checkout.provider;

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    return checkout;
  }

  @override
  Future<PaymentWebhookEvent> verifyAndParseWebhook({
    required Map<String, String> headers,
    required String rawBody,
  }) async {
    return const PaymentWebhookEvent(
      provider: 'paystack',
      providerEventId: 'evt_stub',
      eventType: 'payment_succeeded',
      signatureValid: true,
      purchaseId: null,
      payload: <String, Object?>{},
    );
  }
}
