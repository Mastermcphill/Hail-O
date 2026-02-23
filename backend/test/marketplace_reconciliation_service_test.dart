import 'package:test/test.dart';

import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/marketplace/marketplace_reconciliation_service.dart';

void main() {
  group('MarketplaceReconciliationService', () {
    test(
      'reconcile fixes pending purchase with captured charge and entitlement drift',
      () async {
        final entitlementRepository =
            InMemoryMarketplaceEntitlementRepository();
        final entitlementService = MarketplaceEntitlementService(
          repository: entitlementRepository,
        );
        final purchase = _purchase(
          status: 'PENDING',
          seatCount: 3,
          offerId: 'offer_sedan_01',
        );
        await entitlementRepository.rotateEntitlement(
          purchaseId: purchase.id,
          userId: purchase.userId,
          entitlementType: 'seats',
          value: const <String, Object?>{'seats_total': 7},
        );
        await entitlementRepository.rotateEntitlement(
          purchaseId: purchase.id,
          userId: purchase.userId,
          entitlementType: 'plan',
          value: const <String, Object?>{'plan': 'offer_wrong_01'},
        );

        final store = _FakeReconciliationStore(
          purchase: purchase,
          entitlementRepository: entitlementRepository,
          ledgerEntries: <BillingLedgerEntryRecord>[
            _ledger(
              purchaseId: purchase.id,
              userId: purchase.userId,
              entryType: 'charge_captured',
              amountMinor: purchase.totalAmountMinor,
            ),
          ],
        );
        final service = MarketplaceReconciliationService(
          store: store,
          entitlementService: entitlementService,
        );

        final result = await service.reconcile(
          purchaseId: purchase.id,
          traceId: 'trace-reconcile-1',
          dryRun: false,
        );

        expect(result, isNotNull);
        expect(result!.driftDetected, isTrue);
        expect(result.applied, isTrue);
        expect(result.expectedStatus, 'ACTIVE');
        expect(store.currentPurchase.status, 'ACTIVE');
        final activeAfter = (await entitlementRepository.listActiveByPurchase(
          purchaseId: purchase.id,
        ));
        expect(activeAfter.length, 2);
        expect(
          activeAfter
              .firstWhere((row) => row.entitlementType == 'seats')
              .value['seats_total'],
          3,
        );
        expect(
          activeAfter
              .firstWhere((row) => row.entitlementType == 'plan')
              .value['plan'],
          'offer_sedan_01',
        );
        expect(
          store.timeline.any((event) => event.eventType == 'reconciled'),
          isTrue,
        );
      },
    );

    test(
      'reconcile revokes entitlements when refund/chargeback is latest truth',
      () async {
        final entitlementRepository =
            InMemoryMarketplaceEntitlementRepository();
        final entitlementService = MarketplaceEntitlementService(
          repository: entitlementRepository,
        );
        final purchase = _purchase(
          status: 'ACTIVE',
          seatCount: 2,
          offerId: 'offer_suv_02',
        );
        await entitlementService.syncPurchaseEntitlements(
          purchase: purchase,
          reason: 'seed_active',
        );

        final store = _FakeReconciliationStore(
          purchase: purchase,
          entitlementRepository: entitlementRepository,
          ledgerEntries: <BillingLedgerEntryRecord>[
            _ledger(
              purchaseId: purchase.id,
              userId: purchase.userId,
              entryType: 'refund_succeeded',
              amountMinor: -purchase.totalAmountMinor,
            ),
          ],
        );
        final service = MarketplaceReconciliationService(
          store: store,
          entitlementService: entitlementService,
        );
        final result = await service.reconcile(
          purchaseId: purchase.id,
          traceId: 'trace-reconcile-2',
          dryRun: false,
        );

        expect(result, isNotNull);
        expect(result!.expectedStatus, 'CANCELED');
        expect(store.currentPurchase.status, 'CANCELED');
        final activeAfter = await entitlementRepository.listActiveByPurchase(
          purchaseId: purchase.id,
        );
        expect(activeAfter, isEmpty);
      },
    );
  });
}

class _FakeReconciliationStore implements MarketplaceReconciliationStore {
  _FakeReconciliationStore({
    required MarketplacePurchaseRecord purchase,
    required MarketplaceEntitlementRepository entitlementRepository,
    required List<BillingLedgerEntryRecord> ledgerEntries,
    List<MarketplaceTimelineEventRecord>? timeline,
    List<MarketplaceWebhookEventSummary>? webhooks,
  }) : currentPurchase = purchase,
       _entitlementRepository = entitlementRepository,
       _ledgerEntries = ledgerEntries,
       this.timeline = timeline ?? <MarketplaceTimelineEventRecord>[],
       _webhooks = webhooks ?? <MarketplaceWebhookEventSummary>[];

  MarketplacePurchaseRecord currentPurchase;
  final MarketplaceEntitlementRepository _entitlementRepository;
  final List<BillingLedgerEntryRecord> _ledgerEntries;
  final List<MarketplaceWebhookEventSummary> _webhooks;
  final List<MarketplaceTimelineEventRecord> timeline;

  @override
  Future<void> appendTimeline({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) async {
    timeline.add(
      MarketplaceTimelineEventRecord(
        id: 'timeline-${timeline.length + 1}',
        purchaseId: purchaseId,
        eventType: eventType,
        eventData: eventData,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById(String purchaseId) async {
    if (purchaseId != currentPurchase.id) {
      return null;
    }
    return currentPurchase;
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
  }) async {
    return _ledgerEntries
        .where((entry) => entry.purchaseId == purchaseId)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceTimelineEventRecord>> listTimelineByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    return timeline
        .where((entry) => entry.purchaseId == purchaseId)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceWebhookEventSummary>> listWebhooksByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    return _webhooks.take(limit).toList(growable: false);
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
  }) async {
    currentPurchase = MarketplacePurchaseRecord(
      id: currentPurchase.id,
      userId: currentPurchase.userId,
      offerId: currentPurchase.offerId,
      offerTitle: currentPurchase.offerTitle,
      status: status,
      currency: currentPurchase.currency,
      totalAmountMinor: currentPurchase.totalAmountMinor,
      seatCount: currentPurchase.seatCount,
      idempotencyKey: currentPurchase.idempotencyKey,
      createdAt: currentPurchase.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

MarketplacePurchaseRecord _purchase({
  required String status,
  required int seatCount,
  required String offerId,
}) {
  return MarketplacePurchaseRecord(
    id: '2f15644e-74d1-4952-b45c-55c3695d58dc',
    userId: 'user-reconcile-1',
    offerId: offerId,
    offerTitle: 'Offer',
    status: status,
    currency: 'NGN',
    totalAmountMinor: seatCount * 4200,
    seatCount: seatCount,
    idempotencyKey: 'idem-reconcile-1',
    createdAt: DateTime.utc(2026, 2, 23),
    updatedAt: DateTime.utc(2026, 2, 23),
  );
}

BillingLedgerEntryRecord _ledger({
  required String purchaseId,
  required String userId,
  required String entryType,
  required int amountMinor,
}) {
  return BillingLedgerEntryRecord(
    id: 'ledger-$entryType',
    purchaseId: purchaseId,
    userId: userId,
    entryType: entryType,
    provider: 'manual',
    providerRef: 'provider-ref-$entryType',
    amountMinor: amountMinor,
    currency: 'NGN',
    metadata: const <String, Object?>{'source': 'test'},
    occurredAt: DateTime.utc(2026, 2, 23),
    createdAt: DateTime.utc(2026, 2, 23),
  );
}
