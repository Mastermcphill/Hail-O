import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../infra/postgres_provider.dart';
import 'billing_ledger_repository.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_offer_repository.dart';

class MarketplaceWebhookEventSummary {
  const MarketplaceWebhookEventSummary({
    required this.provider,
    required this.providerEventId,
    required this.eventType,
    required this.signatureValid,
    required this.processed,
    required this.createdAt,
  });

  final String provider;
  final String providerEventId;
  final String eventType;
  final bool signatureValid;
  final bool processed;
  final DateTime createdAt;
}

abstract class MarketplaceReconciliationStore {
  Future<MarketplacePurchaseRecord?> findPurchaseById(String purchaseId);

  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
  });

  Future<List<BillingLedgerEntryRecord>> listLedgerByPurchase(
    String purchaseId, {
    int limit = 200,
  });

  Future<List<MarketplaceEntitlementRecord>> listEntitlementsByPurchase(
    String purchaseId, {
    int limit = 200,
  });

  Future<List<MarketplaceTimelineEventRecord>> listTimelineByPurchase(
    String purchaseId, {
    int limit = 200,
  });

  Future<List<MarketplaceWebhookEventSummary>> listWebhooksByPurchase(
    String purchaseId, {
    int limit = 200,
  });

  Future<void> appendTimeline({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  });
}

class PostgresMarketplaceReconciliationStore
    implements MarketplaceReconciliationStore {
  PostgresMarketplaceReconciliationStore(this._postgresProvider, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final PostgresProvider _postgresProvider;
  final Uuid _uuid;

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById(String purchaseId) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          p.id::text,
          p.user_id,
          p.offer_id,
          p.status,
          p.currency,
          p.price_minor,
          p.seats_total,
          p.idempotency_key,
          p.created_at,
          p.updated_at,
          o.title
        FROM marketplace_purchases p
        JOIN marketplace_offers o
          ON o.id = p.offer_id
        WHERE p.id = CAST(@purchase_id AS UUID)
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'purchase_id': purchaseId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return MarketplacePurchaseRecord(
      id: (row[0] as String?)?.trim() ?? '',
      userId: (row[1] as String?)?.trim() ?? '',
      offerId: (row[2] as String?)?.trim() ?? '',
      status: (row[3] as String?)?.trim() ?? '',
      currency: (row[4] as String?)?.trim() ?? 'NGN',
      totalAmountMinor: (row[5] as num?)?.toInt() ?? 0,
      seatCount: (row[6] as num?)?.toInt() ?? 0,
      idempotencyKey: (row[7] as String?)?.trim() ?? '',
      createdAt: _readDateTime(row[8]),
      updatedAt: _readDateTime(row[9]),
      offerTitle: (row[10] as String?)?.trim() ?? '',
    );
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
  }) {
    return _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        UPDATE marketplace_purchases
        SET status = @status, updated_at = NOW()
        WHERE id = CAST(@purchase_id AS UUID)
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'status': status,
        },
      ),
    );
  }

  @override
  Future<List<BillingLedgerEntryRecord>> listLedgerByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          user_id,
          entry_type,
          provider,
          provider_ref,
          amount_minor,
          currency,
          metadata::text,
          occurred_at,
          created_at
        FROM billing_ledger_entries
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY occurred_at DESC, created_at DESC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'limit': limit < 1 ? 1 : limit,
        },
      ),
    );
    return rows
        .map(
          (row) => BillingLedgerEntryRecord(
            id: (row[0] as String?)?.trim() ?? '',
            purchaseId: (row[1] as String?)?.trim(),
            userId: (row[2] as String?)?.trim() ?? '',
            entryType: (row[3] as String?)?.trim() ?? '',
            provider: (row[4] as String?)?.trim() ?? '',
            providerRef: (row[5] as String?)?.trim() ?? '',
            amountMinor: (row[6] as num?)?.toInt() ?? 0,
            currency: (row[7] as String?)?.trim() ?? 'NGN',
            metadata: _decodeMap(row[8]),
            occurredAt: _readDateTime(row[9]),
            createdAt: _readDateTime(row[10]),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceEntitlementRecord>> listEntitlementsByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          user_id,
          entitlement_type,
          value_json::text,
          status,
          effective_from,
          effective_to,
          created_at,
          updated_at
        FROM marketplace_entitlements
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY effective_from ASC, created_at ASC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'limit': limit < 1 ? 1 : limit,
        },
      ),
    );
    return rows
        .map(
          (row) => MarketplaceEntitlementRecord(
            id: (row[0] as String?)?.trim() ?? '',
            purchaseId: (row[1] as String?)?.trim() ?? '',
            userId: (row[2] as String?)?.trim() ?? '',
            entitlementType: (row[3] as String?)?.trim() ?? '',
            value: _decodeMap(row[4]),
            status: (row[5] as String?)?.trim() ?? '',
            effectiveFrom: _readDateTime(row[6]),
            effectiveTo: row[7] == null ? null : _readDateTime(row[7]),
            createdAt: _readDateTime(row[8]),
            updatedAt: _readDateTime(row[9]),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceTimelineEventRecord>> listTimelineByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          id::text,
          purchase_id::text,
          event_type,
          event_data::text,
          created_at
        FROM marketplace_timeline_events
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY created_at ASC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'limit': limit < 1 ? 1 : limit,
        },
      ),
    );
    return rows
        .map(
          (row) => MarketplaceTimelineEventRecord(
            id: (row[0] as String?)?.trim() ?? '',
            purchaseId: (row[1] as String?)?.trim() ?? '',
            eventType: (row[2] as String?)?.trim() ?? '',
            eventData: _decodeMap(row[3]),
            createdAt: _readDateTime(row[4]),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MarketplaceWebhookEventSummary>> listWebhooksByPurchase(
    String purchaseId, {
    int limit = 200,
  }) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT
          provider,
          provider_event_id,
          event_type,
          signature_valid,
          processed,
          created_at
        FROM marketplace_webhook_events
        WHERE purchase_id = CAST(@purchase_id AS UUID)
        ORDER BY created_at DESC
        LIMIT @limit
        ''',
        substitutionValues: <String, Object?>{
          'purchase_id': purchaseId,
          'limit': limit < 1 ? 1 : limit,
        },
      ),
    );
    return rows
        .map(
          (row) => MarketplaceWebhookEventSummary(
            provider: (row[0] as String?)?.trim() ?? '',
            providerEventId: (row[1] as String?)?.trim() ?? '',
            eventType: (row[2] as String?)?.trim() ?? '',
            signatureValid: row[3] == true,
            processed: row[4] == true,
            createdAt: _readDateTime(row[5]),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> appendTimeline({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
  }) {
    return _postgresProvider.withConnection(
      (connection) => connection.execute(
        '''
        INSERT INTO marketplace_timeline_events(
          id,
          purchase_id,
          event_type,
          event_data,
          created_at
        )
        VALUES(
          @id,
          CAST(@purchase_id AS UUID),
          @event_type,
          CAST(@event_data AS JSONB),
          NOW()
        )
        ''',
        substitutionValues: <String, Object?>{
          'id': _uuid.v4(),
          'purchase_id': purchaseId,
          'event_type': eventType,
          'event_data': jsonEncode(eventData),
        },
      ),
    );
  }

  Map<String, Object?> _decodeMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return <String, Object?>{};
      }
    }
    return <String, Object?>{};
  }

  DateTime _readDateTime(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    return DateTime.now().toUtc();
  }
}

class MarketplaceReconciliationResult {
  const MarketplaceReconciliationResult({
    required this.purchaseId,
    required this.currentStatus,
    required this.expectedStatus,
    required this.finalStatus,
    required this.driftDetected,
    required this.applied,
    required this.driftReasons,
    required this.ledgerEntries,
    required this.entitlementsBefore,
    required this.entitlementsAfter,
    required this.webhookEvents,
    required this.timelineEvents,
  });

  final String purchaseId;
  final String currentStatus;
  final String expectedStatus;
  final String finalStatus;
  final bool driftDetected;
  final bool applied;
  final List<String> driftReasons;
  final List<BillingLedgerEntryRecord> ledgerEntries;
  final List<MarketplaceEntitlementRecord> entitlementsBefore;
  final List<MarketplaceEntitlementRecord> entitlementsAfter;
  final List<MarketplaceWebhookEventSummary> webhookEvents;
  final List<MarketplaceTimelineEventRecord> timelineEvents;
}

class MarketplaceReconciliationService {
  MarketplaceReconciliationService({
    required MarketplaceReconciliationStore store,
    required MarketplaceEntitlementService entitlementService,
    void Function(String line)? logSink,
  }) : _store = store,
       _entitlementService = entitlementService,
       _logSink = logSink ?? print;

  final MarketplaceReconciliationStore _store;
  final MarketplaceEntitlementService _entitlementService;
  final void Function(String line) _logSink;

  Future<MarketplaceReconciliationResult?> reconcile({
    required String purchaseId,
    required String traceId,
    bool dryRun = false,
  }) async {
    final purchase = await _store.findPurchaseById(purchaseId);
    if (purchase == null) {
      return null;
    }

    final ledgerEntries = await _store.listLedgerByPurchase(purchaseId);
    final entitlementsBefore = await _store.listEntitlementsByPurchase(
      purchaseId,
    );
    final webhookEvents = await _store.listWebhooksByPurchase(purchaseId);
    final timelineBefore = await _store.listTimelineByPurchase(purchaseId);
    final expectedStatus = _expectedStatusFromLedger(
      ledgerEntries: ledgerEntries,
      fallbackStatus: purchase.status,
    );

    final driftReasons = <String>[];
    if (purchase.status.trim().toUpperCase() != expectedStatus) {
      driftReasons.add(
        'status_mismatch:${purchase.status.trim().toUpperCase()}->$expectedStatus',
      );
    }

    final activeEntitlements = entitlementsBefore
        .where((entry) => entry.status == 'active' && entry.effectiveTo == null)
        .toList(growable: false);
    final activeSeats = activeEntitlements.where(
      (entry) => entry.entitlementType == 'seats',
    );
    final activePlan = activeEntitlements.where(
      (entry) => entry.entitlementType == 'plan',
    );
    final seatDrift = activeSeats.any(
      (entry) =>
          _toInt(entry.value['seats_total']) == null ||
          _toInt(entry.value['seats_total'])! > purchase.seatCount ||
          _toInt(entry.value['seats_total']) != purchase.seatCount,
    );
    if (seatDrift) {
      driftReasons.add('seat_entitlement_mismatch');
    }
    final planDrift = activePlan.any(
      (entry) => (entry.value['plan'] ?? '').toString() != purchase.offerId,
    );
    if (planDrift) {
      driftReasons.add('plan_entitlement_mismatch');
    }
    if (expectedStatus != 'ACTIVE' && activeEntitlements.isNotEmpty) {
      driftReasons.add('entitlements_should_be_revoked');
    }
    if (expectedStatus == 'ACTIVE' && activeEntitlements.isEmpty) {
      driftReasons.add('entitlements_missing');
    }

    final driftDetected = driftReasons.isNotEmpty;
    var finalStatus = purchase.status.trim().toUpperCase();

    if (driftDetected && !dryRun) {
      if (finalStatus != expectedStatus) {
        await _store.updatePurchaseStatus(
          purchaseId: purchaseId,
          status: expectedStatus,
        );
        finalStatus = expectedStatus;
      }
      final normalizedPurchase = MarketplacePurchaseRecord(
        id: purchase.id,
        userId: purchase.userId,
        offerId: purchase.offerId,
        offerTitle: purchase.offerTitle,
        status: finalStatus,
        currency: purchase.currency,
        totalAmountMinor: purchase.totalAmountMinor,
        seatCount: purchase.seatCount,
        idempotencyKey: purchase.idempotencyKey,
        createdAt: purchase.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
      await _entitlementService.syncPurchaseEntitlements(
        purchase: normalizedPurchase,
        reason: 'reconciliation',
      );
      await _store.appendTimeline(
        purchaseId: purchaseId,
        eventType: 'reconciled',
        eventData: <String, Object?>{
          'trace_id': traceId,
          'expected_status': expectedStatus,
          'previous_status': purchase.status,
          'drift_reasons': driftReasons,
        },
      );
    }

    final entitlementsAfter = await _store.listEntitlementsByPurchase(
      purchaseId,
    );
    final timelineAfter = await _store.listTimelineByPurchase(purchaseId);
    _logSink(
      jsonEncode(<String, Object?>{
        'component': 'marketplace_reconciliation',
        'trace_id': traceId,
        'purchase_id': purchaseId,
        'dry_run': dryRun,
        'drift_detected': driftDetected,
        'expected_status': expectedStatus,
        'current_status': purchase.status,
        'final_status': dryRun ? purchase.status : finalStatus,
        'drift_reasons': driftReasons,
      }),
    );

    return MarketplaceReconciliationResult(
      purchaseId: purchaseId,
      currentStatus: purchase.status,
      expectedStatus: expectedStatus,
      finalStatus: dryRun ? purchase.status : finalStatus,
      driftDetected: driftDetected,
      applied: driftDetected && !dryRun,
      driftReasons: driftReasons,
      ledgerEntries: ledgerEntries,
      entitlementsBefore: entitlementsBefore,
      entitlementsAfter: entitlementsAfter,
      webhookEvents: webhookEvents,
      timelineEvents: driftDetected && !dryRun ? timelineAfter : timelineBefore,
    );
  }

  String _expectedStatusFromLedger({
    required List<BillingLedgerEntryRecord> ledgerEntries,
    required String fallbackStatus,
  }) {
    final normalizedFallback = fallbackStatus.trim().toUpperCase().isEmpty
        ? 'PENDING'
        : fallbackStatus.trim().toUpperCase();
    if (ledgerEntries.isEmpty) {
      return normalizedFallback;
    }
    final hasReversal = ledgerEntries.any(
      (entry) =>
          entry.entryType == 'refund_succeeded' ||
          entry.entryType == 'chargeback',
    );
    if (hasReversal) {
      return 'CANCELED';
    }
    final hasCapture = ledgerEntries.any(
      (entry) =>
          entry.entryType == 'charge_captured' ||
          entry.entryType == 'invoice_paid',
    );
    if (hasCapture) {
      return 'ACTIVE';
    }
    final hasFailed = ledgerEntries.any(
      (entry) => entry.entryType == 'charge_failed',
    );
    if (hasFailed) {
      return 'PAST_DUE';
    }
    return 'PENDING';
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
