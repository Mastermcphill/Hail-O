import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../lib/domain/services/wallet_reversal_service.dart';
import '../modules/admin/admin_controller.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/marketplace/marketplace_reconciliation_service.dart';
import '../infra/request_context.dart';

void main() {
  group('marketplace admin endpoints', () {
    test('debug and reconcile endpoints return support payloads', () async {
      final entitlementRepository = InMemoryMarketplaceEntitlementRepository();
      final entitlementService = MarketplaceEntitlementService(
        repository: entitlementRepository,
      );
      final purchase = MarketplacePurchaseRecord(
        id: '2f15644e-74d1-4952-b45c-55c3695d58dc',
        userId: 'user-admin-1',
        offerId: 'offer_sedan_01',
        offerTitle: 'Budget Sedan',
        status: 'PENDING',
        currency: 'NGN',
        totalAmountMinor: 4200,
        seatCount: 1,
        idempotencyKey: 'idem-admin-1',
        createdAt: DateTime.utc(2026, 2, 23),
        updatedAt: DateTime.utc(2026, 2, 23),
      );
      final store = _InMemoryReconciliationStore(
        purchase: purchase,
        entitlementRepository: entitlementRepository,
        ledgerEntries: <BillingLedgerEntryRecord>[
          BillingLedgerEntryRecord(
            id: 'ledger-1',
            purchaseId: purchase.id,
            userId: purchase.userId,
            entryType: 'charge_captured',
            provider: 'manual',
            providerRef: 'provider-ref-1',
            amountMinor: 4200,
            currency: 'NGN',
            metadata: const <String, Object?>{'source': 'test'},
            occurredAt: DateTime.utc(2026, 2, 23),
            createdAt: DateTime.utc(2026, 2, 23),
          ),
        ],
      );
      final reconciliationService = MarketplaceReconciliationService(
        store: store,
        entitlementService: entitlementService,
      );
      final controller = AdminController(
        walletReversalService: WalletReversalService(const _NoopDatabase()),
        runtimeConfigSnapshot: const <String, Object?>{},
        buildInfo: const <String, Object?>{},
        reconciliationService: reconciliationService,
      );
      final handler = controller.router.call;

      final debugResponse = await _send(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/${purchase.id}/debug',
      );
      expect(debugResponse.statusCode, 200);
      final debugBody = await _decode(debugResponse);
      expect(debugBody['ok'], isTrue);
      final debugData = Map<String, Object?>.from(debugBody['data'] as Map);
      expect(debugData.containsKey('purchase'), isTrue);
      expect(debugData.containsKey('ledger_entries'), isTrue);
      expect(debugData.containsKey('reconciliation_dry_run'), isTrue);

      final reconcileResponse = await _send(
        handler,
        method: 'POST',
        path: '/marketplace/purchases/${purchase.id}/reconcile',
      );
      expect(reconcileResponse.statusCode, 200);
      final reconcileBody = await _decode(reconcileResponse);
      expect(reconcileBody['ok'], isTrue);
      final reconcileData = Map<String, Object?>.from(
        reconcileBody['data'] as Map,
      );
      expect(reconcileData['purchase_id'], purchase.id);
      expect(reconcileData['applied'], isTrue);
      expect(
        (reconcileData['after'] as Map<String, Object?>)['status'],
        'ACTIVE',
      );
    });
  });
}

class _InMemoryReconciliationStore implements MarketplaceReconciliationStore {
  _InMemoryReconciliationStore({
    required MarketplacePurchaseRecord purchase,
    required MarketplaceEntitlementRepository entitlementRepository,
    required List<BillingLedgerEntryRecord> ledgerEntries,
  }) : _purchase = purchase,
       _entitlementRepository = entitlementRepository,
       _ledgerEntries = ledgerEntries;

  MarketplacePurchaseRecord _purchase;
  final MarketplaceEntitlementRepository _entitlementRepository;
  final List<BillingLedgerEntryRecord> _ledgerEntries;
  final List<MarketplaceTimelineEventRecord> _timeline =
      <MarketplaceTimelineEventRecord>[];

  @override
  Future<void> appendTimeline({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) async {
    _timeline.add(
      MarketplaceTimelineEventRecord(
        id: 'timeline-${_timeline.length + 1}',
        purchaseId: purchaseId,
        eventType: eventType,
        eventData: eventData,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById(String purchaseId) async {
    return _purchase.id == purchaseId ? _purchase : null;
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
    return _timeline
        .where((entry) => entry.purchaseId == purchaseId)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceWebhookEventSummary>> listWebhooksByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    return const <MarketplaceWebhookEventSummary>[];
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
  }) async {
    _purchase = MarketplacePurchaseRecord(
      id: _purchase.id,
      userId: _purchase.userId,
      offerId: _purchase.offerId,
      offerTitle: _purchase.offerTitle,
      status: status,
      currency: _purchase.currency,
      totalAmountMinor: _purchase.totalAmountMinor,
      seatCount: _purchase.seatCount,
      idempotencyKey: _purchase.idempotencyKey,
      createdAt: _purchase.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class _NoopDatabase implements Database {
  const _NoopDatabase();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Unexpected sqlite access in admin endpoint test');
  }
}

Future<Response> _send(
  Handler handler, {
  required String method,
  required String path,
}) async {
  final request = RequestContext.withContext(
    shelf.Request(method, Uri.parse('http://localhost$path')),
    const RequestContext(
      traceId: 'trace-admin',
      userId: 'admin-1',
      role: 'admin',
    ),
  );
  return handler(request);
}

Future<Map<String, Object?>> _decode(Response response) async {
  final body = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(body as Map<String, dynamic>);
}
