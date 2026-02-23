import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
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
        store: _MapRepositoryReconciliationStore(
          marketplaceRepository: marketplaceRepository,
          billingLedgerRepository: billingLedgerRepository,
          entitlementRepository: entitlementRepository,
        ),
        entitlementService: entitlementService,
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
        purchaseId: purchase['id'] as String,
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
      await entitlementService.syncPurchaseEntitlementsFromMap(
        purchase: updated,
      );

      final allEntitlements = await entitlementService.listByPurchase(
        purchaseId: purchase['id'] as String,
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
        dryRun: false,
      );
      expect(result, isNotNull);
      expect(result!.driftDetected, isTrue);
      expect(result.applied, isTrue);

      final refreshed = await marketplaceRepository.findPurchaseById(
        purchase['id'] as String,
      );
      expect(refreshed!['status'], 'ACTIVE');
    });
  });
}

class _MapRepositoryReconciliationStore implements MarketplaceReconciliationStore {
  _MapRepositoryReconciliationStore({
    required InMemoryMarketplaceRepository marketplaceRepository,
    required BillingLedgerRepository billingLedgerRepository,
    required MarketplaceEntitlementRepository entitlementRepository,
  }) : _marketplaceRepository = marketplaceRepository,
       _billingLedgerRepository = billingLedgerRepository,
       _entitlementRepository = entitlementRepository;

  final InMemoryMarketplaceRepository _marketplaceRepository;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceEntitlementRepository _entitlementRepository;

  @override
  Future<void> appendTimeline({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) {
    return _marketplaceRepository.appendTimelineEvent(
      purchaseId: purchaseId,
      eventType: eventType,
      eventData: eventData,
    );
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById(String purchaseId) async {
    final purchase = await _marketplaceRepository.findPurchaseById(purchaseId);
    if (purchase == null) {
      return null;
    }
    final offerId = (purchase['offer_id'] as String?)?.trim() ?? '';
    final offer = await _marketplaceRepository.findOfferById(offerId);
    return MarketplacePurchaseRecord(
      id: (purchase['id'] as String?)?.trim() ?? '',
      userId: (purchase['user_id'] as String?)?.trim() ?? '',
      offerId: offerId,
      offerTitle: (offer?['title'] as String?)?.trim() ?? offerId,
      status: (purchase['status'] as String?)?.trim() ?? 'PENDING',
      currency: (purchase['currency'] as String?)?.trim() ?? 'NGN',
      totalAmountMinor: (purchase['price_minor'] as num?)?.toInt() ?? 0,
      seatCount: (purchase['seats_total'] as num?)?.toInt() ?? 0,
      idempotencyKey: (purchase['idempotency_key'] as String?)?.trim() ?? '',
      createdAt:
          (purchase['created_at'] as DateTime?)?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt:
          (purchase['updated_at'] as DateTime?)?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<MarketplaceEntitlementRecord>> listEntitlementsByPurchase(
    String purchaseId, {
    int limit = 200,
  }) {
    return _entitlementRepository.listByPurchase(
      purchaseId: purchaseId,
      limit: limit,
    );
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listLedgerByPurchase(
    String purchaseId, {
    int limit = 200,
  }) {
    return _billingLedgerRepository.listByPurchase(
      purchaseId: purchaseId,
      limit: limit,
    );
  }

  @override
  Future<List<MarketplaceTimelineEventRecord>> listTimelineByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _marketplaceRepository.listTimelineEvents(
      purchaseId,
      limit: limit,
    );
    return rows
        .map(
          (row) => MarketplaceTimelineEventRecord(
            id: (row['id'] as String?)?.trim() ?? '',
            purchaseId: (row['purchase_id'] as String?)?.trim() ?? '',
            eventType: (row['event_type'] as String?)?.trim() ?? '',
            eventData: (row['event_data'] is Map<String, Object?>)
                ? (row['event_data'] as Map<String, Object?>)
                : <String, Object?>{},
            createdAt:
                (row['created_at'] as DateTime?)?.toUtc() ??
                DateTime.now().toUtc(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceWebhookEventSummary>> listWebhooksByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _marketplaceRepository.listWebhookEvents(purchaseId);
    return rows
        .take(limit)
        .map(
          (row) => MarketplaceWebhookEventSummary(
            provider: (row['provider'] as String?)?.trim() ?? '',
            providerEventId: (row['provider_event_id'] as String?)?.trim() ?? '',
            eventType: (row['event_type'] as String?)?.trim() ?? '',
            signatureValid: true,
            processed: row['processed'] == true,
            createdAt:
                (row['created_at'] as DateTime?)?.toUtc() ??
                DateTime.now().toUtc(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
  }) {
    return _marketplaceRepository.updatePurchaseStatus(
      purchaseId: purchaseId,
      status: status,
    );
  }
}
