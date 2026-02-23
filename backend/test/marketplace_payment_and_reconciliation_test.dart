import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_reconciliation_service.dart';
import '../modules/marketplace/marketplace_repository_memory.dart';
import '../modules/marketplace/marketplace_timeline_service.dart';
import '../modules/marketplace/payment_service.dart';

void main() {
  group('marketplace payment + reconciliation services', () {
    late InMemoryMarketplaceRepository marketplaceRepository;
    late InMemoryBillingLedgerRepository billingLedgerRepository;
    late InMemoryMarketplaceEntitlementRepository entitlementRepository;
    late MarketplaceEntitlementService entitlementService;
    late MarketplaceTimelineService timelineService;
    late RequestMetrics metrics;
    late PaymentService paymentService;
    late MarketplaceReconciliationService reconciliationService;

    setUp(() {
      marketplaceRepository = InMemoryMarketplaceRepository();
      billingLedgerRepository = InMemoryBillingLedgerRepository();
      entitlementRepository = InMemoryMarketplaceEntitlementRepository();
      entitlementService = MarketplaceEntitlementService(
        entitlementRepository: entitlementRepository,
      );
      timelineService = MarketplaceTimelineService(marketplaceRepository);
      metrics = RequestMetrics();
      paymentService = PaymentService.fromEnvironment(
        environment: const <String, String>{
          'PAYMENT_PROVIDER': 'manual',
          'PAYMENT_WEBHOOK_SECRET': 'manual-secret',
        },
        marketplaceRepository: marketplaceRepository,
        billingLedgerRepository: billingLedgerRepository,
        timelineService: timelineService,
        entitlementService: entitlementService,
        requestMetrics: metrics,
      );
      reconciliationService = MarketplaceReconciliationService(
        marketplaceRepository: marketplaceRepository,
        billingLedgerRepository: billingLedgerRepository,
        entitlementService: entitlementService,
        timelineService: timelineService,
        requestMetrics: metrics,
      );
    });

    Future<Map<String, Object?>> createPurchase({
      String userId = 'user-1',
      String idempotencyKey = 'idem-1',
      int seatCount = 3,
    }) {
      return marketplaceRepository.createOrReusePurchase(
        userId: userId,
        offerId: 'starter_monthly',
        seatCount: seatCount,
        idempotencyKey: idempotencyKey,
        provider: 'manual',
      );
    }

    test(
      'checkout capture activates purchase and grants entitlements',
      () async {
        final purchase = await createPurchase();

        final checkout = await paymentService.createCheckoutOrIntent(
          purchase: purchase,
        );
        expect(checkout['ok'], true);

        final refreshed = await marketplaceRepository.findPurchaseById(
          purchase['id'] as String,
        );
        expect(refreshed, isNotNull);
        expect(refreshed!['status'], 'active');

        final activeEntitlements = await entitlementService
            .listActiveByPurchase(purchase['id'] as String);
        expect(activeEntitlements.length, 2);
        expect(
          activeEntitlements.map((row) => row.entitlementType).toSet(),
          containsAll(<String>{'plan', 'seats'}),
        );
      },
    );

    test('webhook replay does not duplicate ledger entries', () async {
      final purchase = await createPurchase();
      await paymentService.createCheckoutOrIntent(purchase: purchase);

      Request webhookRequest() {
        return Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{
            'content-type': 'application/json',
            'x-manual-signature': 'manual-secret',
          },
          body: jsonEncode(<String, Object?>{
            'event_id': 'evt-dup-1',
            'event_type': 'refund_succeeded',
            'purchase_id': purchase['id'],
            'amount_minor': 150000,
            'currency': 'NGN',
          }),
        );
      }

      final first = await paymentService.handleWebhook(webhookRequest());
      final second = await paymentService.handleWebhook(webhookRequest());
      expect(first.success, isTrue);
      expect(first.action, 'refund');
      expect(second.success, isTrue);
      expect(second.action, 'duplicate');

      final ledger = await billingLedgerRepository.listByPurchase(
        purchase['id'] as String,
      );
      final refunds = ledger
          .where((entry) => entry.entryType == 'refund_succeeded')
          .toList(growable: false);
      expect(refunds.length, 1);
    });

    test('refund revokes entitlements and updates purchase status', () async {
      final purchase = await createPurchase();
      await paymentService.createCheckoutOrIntent(purchase: purchase);

      final refundOutcome = await paymentService.handleWebhook(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/payments'),
          headers: const <String, String>{
            'content-type': 'application/json',
            'x-manual-signature': 'manual-secret',
          },
          body: jsonEncode(<String, Object?>{
            'event_id': 'evt-refund-1',
            'event_type': 'refund_succeeded',
            'purchase_id': purchase['id'],
            'amount_minor': 150000,
            'currency': 'NGN',
          }),
        ),
      );
      expect(refundOutcome.success, isTrue);

      final refreshed = await marketplaceRepository.findPurchaseById(
        purchase['id'] as String,
      );
      expect(refreshed!['status'], 'refunded');

      final activeEntitlements = await entitlementService.listActiveByPurchase(
        purchase['id'] as String,
      );
      expect(activeEntitlements, isEmpty);
    });

    test('seat change rotates seat entitlement rows', () async {
      final purchase = await createPurchase(seatCount: 2);
      await paymentService.createCheckoutOrIntent(purchase: purchase);

      final updated = await marketplaceRepository.updatePurchaseSeats(
        purchaseId: purchase['id'] as String,
        seatCount: 7,
      );
      await entitlementService.syncPurchaseEntitlements(updated);

      final allEntitlements = await entitlementService.listByPurchase(
        purchase['id'] as String,
      );
      final seatRows = allEntitlements
          .where((row) => row.entitlementType == 'seats')
          .toList(growable: false);
      expect(seatRows.length, greaterThanOrEqualTo(2));
      expect(
        seatRows.any((row) => row.effectiveToUtc != null),
        isTrue,
        reason: 'previous seat entitlement should be closed',
      );
      final active = seatRows.firstWhere((row) => row.effectiveToUtc == null);
      expect((active.valueJson['seats_total'] as num?)?.toInt(), 7);
    });

    test('reconciliation repairs corrupted purchase state', () async {
      final purchase = await createPurchase();
      await paymentService.createCheckoutOrIntent(purchase: purchase);

      await marketplaceRepository.updatePurchaseStatus(
        purchaseId: purchase['id'] as String,
        status: 'pending',
      );

      final result = await reconciliationService.reconcile(
        purchaseId: purchase['id'] as String,
        traceId: 'test-trace-1',
        apply: true,
      );
      expect(result, isNotNull);
      expect(result!.driftDetected, isTrue);
      expect(result.applied, isTrue);

      final refreshed = await marketplaceRepository.findPurchaseById(
        purchase['id'] as String,
      );
      expect(refreshed!['status'], 'active');
    });
  });
}
