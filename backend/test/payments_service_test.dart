import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/in_memory_marketplace_offer_repository.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/payments/manual_payment_provider.dart';
import '../modules/payments/payment_intent_repository.dart';
import '../modules/payments/payment_webhook_event_repository.dart';
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
      'deduplicates signed paystack webhooks by provider_event_id',
      () async {
        const webhookSecret = 'paystack-webhook-secret';
        final service = PaymentService(
          provider: PaystackPaymentProvider(
            secretKey: 'sk_test_key',
            webhookSecret: webhookSecret,
          ),
        );
        final body = jsonEncode(<String, Object?>{
          'event': 'charge.success',
          'data': <String, Object?>{
            'id': 'evt-paystack-dedupe-1',
            'metadata': <String, Object?>{
              'purchase_id': '3f5720c3-fc3b-450d-9760-404f476fddf2',
            },
          },
        });
        final signature = Hmac(
          sha512,
          utf8.encode(webhookSecret),
        ).convert(utf8.encode(body)).toString();

        final first = await service.handleWebhook(
          headers: <String, String>{'x-paystack-signature': signature},
          rawBody: body,
        );
        final second = await service.handleWebhook(
          headers: <String, String>{'x-paystack-signature': signature},
          rawBody: body,
        );
        expect(first.duplicate, isFalse);
        expect(second.duplicate, isTrue);
        expect(second.action, 'duplicate_ignored');
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
      'failed webhook processing is retried from stored pending event',
      () async {
        final offerRepository = InMemoryMarketplaceOfferRepository();
        final intentRepository = InMemoryPaymentIntentRepository();
        final webhookRepository = InMemoryPaymentWebhookEventRepository();
        final flakyLedger = _FlakyBillingLedgerRepository(
          failEntryType: 'charge_captured',
          failuresBeforeSuccess: 1,
        );
        var now = DateTime.utc(2026, 2, 1, 12, 0, 0);
        final service = PaymentService(
          provider: ManualPaymentProvider(),
          offerRepository: offerRepository,
          paymentIntentRepository: intentRepository,
          paymentWebhookEventRepository: webhookRepository,
          billingLedgerRepository: flakyLedger,
          nowUtc: () => now,
        );

        final purchase = await offerRepository.createOrGetPurchase(
          userId: 'webhook-retry-user-1',
          offerId: 'offer_sedan_01',
          seatCount: 1,
          idempotencyKey: 'webhook-retry-idem-1',
          provider: 'paystack',
        );
        final intent = await service.createPaymentIntent(
          userId: purchase.userId,
          purchaseId: purchase.id,
        );

        final body = jsonEncode(<String, Object?>{
          'provider_event_id': 'evt-retry-1',
          'event_type': 'payment_succeeded',
          'purchase_id': purchase.id,
          'amount_minor': purchase.totalAmountMinor,
          'currency': purchase.currency,
        });

        await expectLater(
          service.handleWebhook(
            headers: const <String, String>{},
            rawBody: body,
          ),
          throwsA(isA<StateError>()),
        );

        final pending = await webhookRepository.findEvent(
          provider: 'manual',
          eventId: 'evt-retry-1',
        );
        expect(pending, isNotNull);
        expect(pending!.processingState, 'pending_processing');
        expect(pending.attemptCount, 1);
        expect((pending.lastError ?? '').isNotEmpty, isTrue);

        now = now.add(const Duration(minutes: 1));
        final retryResult = await service.retryPendingWebhooks(limit: 5);
        expect(retryResult.scanned, 1);
        expect(retryResult.retried, 1);
        expect(retryResult.rescheduled, 0);
        expect(retryResult.failed, 0);

        final processed = await webhookRepository.findEvent(
          provider: 'manual',
          eventId: 'evt-retry-1',
        );
        expect(processed, isNotNull);
        expect(processed!.processingState, 'processed');
        expect(processed.attemptCount, 2);

        final updatedIntent = await service.getPaymentIntentForUser(
          userId: purchase.userId,
          intentId: intent.id,
        );
        expect(updatedIntent, isNotNull);
        expect(updatedIntent!.status, 'succeeded');
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

class _FlakyBillingLedgerRepository implements BillingLedgerRepository {
  _FlakyBillingLedgerRepository({
    required String failEntryType,
    required int failuresBeforeSuccess,
  }) : _failEntryType = failEntryType.trim().toLowerCase(),
       _failuresLeft = failuresBeforeSuccess;

  final InMemoryBillingLedgerRepository _delegate =
      InMemoryBillingLedgerRepository();
  final String _failEntryType;
  int _failuresLeft;

  @override
  Future<bool> append(BillingLedgerEntryRecord entry) {
    return appendEntry(
      purchaseId: entry.purchaseId,
      userId: entry.userId,
      entryType: entry.entryType,
      provider: entry.provider,
      providerRef: entry.providerRef,
      amountMinor: entry.amountMinor,
      currency: entry.currency,
      metadata: entry.metadata,
      occurredAt: entry.occurredAt,
    );
  }

  @override
  Future<bool> appendEntry({
    required String? purchaseId,
    required String userId,
    required String entryType,
    required String provider,
    required String providerRef,
    required int amountMinor,
    required String currency,
    required Map<String, Object?> metadata,
    DateTime? occurredAt,
  }) async {
    if (_failuresLeft > 0 && entryType.trim().toLowerCase() == _failEntryType) {
      _failuresLeft -= 1;
      throw StateError('simulated_ledger_failure');
    }
    return _delegate.appendEntry(
      purchaseId: purchaseId,
      userId: userId,
      entryType: entryType,
      provider: provider,
      providerRef: providerRef,
      amountMinor: amountMinor,
      currency: currency,
      metadata: metadata,
      occurredAt: occurredAt,
    );
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByPurchase({
    required String purchaseId,
    int limit = 200,
  }) {
    return _delegate.listByPurchase(purchaseId: purchaseId, limit: limit);
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listByUser({
    required String userId,
    int limit = 200,
  }) {
    return _delegate.listByUser(userId: userId, limit: limit);
  }
}
