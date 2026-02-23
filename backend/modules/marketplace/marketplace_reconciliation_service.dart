import 'dart:convert';

import '../../infra/request_metrics.dart';
import 'billing_ledger_repository.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_repository.dart';
import 'marketplace_timeline_service.dart';

class MarketplaceReconciliationResult {
  const MarketplaceReconciliationResult({
    required this.purchaseId,
    required this.beforeStatus,
    required this.expectedStatus,
    required this.afterStatus,
    required this.driftDetected,
    required this.applied,
    required this.reasons,
    required this.entitlementDrift,
    required this.purchase,
  });

  final String purchaseId;
  final String beforeStatus;
  final String expectedStatus;
  final String afterStatus;
  final bool driftDetected;
  final bool applied;
  final List<String> reasons;
  final bool entitlementDrift;
  final Map<String, Object?> purchase;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'purchase_id': purchaseId,
      'before_status': beforeStatus,
      'expected_status': expectedStatus,
      'after_status': afterStatus,
      'drift_detected': driftDetected,
      'applied': applied,
      'reasons': reasons,
      'entitlement_drift': entitlementDrift,
      'purchase': _jsonSafe(purchase) as Map<String, Object?>,
    };
  }

  Object? _jsonSafe(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonSafe(item)),
      );
    }
    if (value is List) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    return value;
  }
}

class MarketplaceReconciliationService {
  MarketplaceReconciliationService({
    required MarketplaceRepository marketplaceRepository,
    required BillingLedgerRepository billingLedgerRepository,
    required MarketplaceEntitlementService entitlementService,
    required MarketplaceTimelineService timelineService,
    required RequestMetrics requestMetrics,
    void Function(String line)? logSink,
  }) : _marketplaceRepository = marketplaceRepository,
       _billingLedgerRepository = billingLedgerRepository,
       _entitlementService = entitlementService,
       _timelineService = timelineService,
       _requestMetrics = requestMetrics,
       _logSink = logSink ?? print;

  final MarketplaceRepository _marketplaceRepository;
  final BillingLedgerRepository _billingLedgerRepository;
  final MarketplaceEntitlementService _entitlementService;
  final MarketplaceTimelineService _timelineService;
  final RequestMetrics _requestMetrics;
  final void Function(String line) _logSink;

  Future<MarketplaceReconciliationResult?> reconcile({
    required String purchaseId,
    required String traceId,
    bool apply = false,
  }) async {
    final watch = Stopwatch()..start();
    final purchase = await _marketplaceRepository.findPurchaseById(purchaseId);
    if (purchase == null) {
      return null;
    }
    final ledgerEntries = await _billingLedgerRepository.listByPurchase(
      purchaseId,
    );
    final entitlements = await _entitlementService.listActiveByPurchase(
      purchaseId,
    );
    final beforeStatus =
        (purchase['status'] as String?)?.trim().toLowerCase() ?? 'pending';
    final expectedStatus = _deriveStatus(beforeStatus, ledgerEntries);

    final reasons = <String>[];
    if (beforeStatus != expectedStatus) {
      reasons.add('status_mismatch');
    }

    final seatsTotal = (purchase['seats_total'] as num?)?.toInt() ?? 1;
    final entitlementDrift = _hasEntitlementDrift(
      expectedStatus: expectedStatus,
      seatsTotal: seatsTotal,
      offerId: (purchase['offer_id'] as String?) ?? 'unknown',
      activeEntitlements: entitlements,
      reasons: reasons,
    );

    final driftDetected = beforeStatus != expectedStatus || entitlementDrift;
    var afterStatus = beforeStatus;
    var applied = false;
    if (apply && driftDetected) {
      if (beforeStatus != expectedStatus) {
        await _marketplaceRepository.updatePurchaseStatus(
          purchaseId: purchaseId,
          status: expectedStatus,
        );
        afterStatus = expectedStatus;
      }
      final refreshed = await _marketplaceRepository.findPurchaseById(
        purchaseId,
      );
      if (refreshed != null) {
        await _entitlementService.syncPurchaseEntitlements(refreshed);
      }
      await _timelineService.appendEvent(
        purchaseId: purchaseId,
        type: 'reconciled',
        data: <String, Object?>{
          'before_status': beforeStatus,
          'expected_status': expectedStatus,
          'reasons': reasons,
          'entitlement_drift': entitlementDrift,
        },
      );
      applied = true;
    }

    _requestMetrics.recordMarketplaceReconciliation(
      driftDetected: driftDetected,
      applied: applied,
      dryRun: !apply,
    );
    watch.stop();
    _logSink(
      jsonEncode(<String, Object?>{
        'trace_id': traceId,
        'route': '/admin/marketplace/purchases/:id/reconcile',
        'purchase_id': purchaseId,
        'drift_detected': driftDetected,
        'applied': applied,
        'before_status': beforeStatus,
        'expected_status': expectedStatus,
        'after_status': applied ? afterStatus : beforeStatus,
        'latency_ms': watch.elapsedMilliseconds,
      }),
    );

    final finalPurchase = await _marketplaceRepository.findPurchaseById(
      purchaseId,
    );
    return MarketplaceReconciliationResult(
      purchaseId: purchaseId,
      beforeStatus: beforeStatus,
      expectedStatus: expectedStatus,
      afterStatus: applied ? afterStatus : beforeStatus,
      driftDetected: driftDetected,
      applied: applied,
      reasons: reasons,
      entitlementDrift: entitlementDrift,
      purchase: finalPurchase ?? purchase,
    );
  }

  String _deriveStatus(
    String currentStatus,
    List<BillingLedgerEntryRecord> entries,
  ) {
    if (entries.any((entry) => entry.entryType == 'chargeback')) {
      return 'refunded';
    }
    if (entries.any((entry) => entry.entryType == 'refund_succeeded')) {
      return 'refunded';
    }
    if (entries.any((entry) => entry.entryType == 'charge_failed')) {
      return 'past_due';
    }
    if (entries.any(
      (entry) =>
          entry.entryType == 'charge_captured' ||
          entry.entryType == 'invoice_paid',
    )) {
      return 'active';
    }
    if (currentStatus == 'canceled' || currentStatus == 'cancelled') {
      return 'canceled';
    }
    return 'pending';
  }

  bool _hasEntitlementDrift({
    required String expectedStatus,
    required int seatsTotal,
    required String offerId,
    required List<MarketplaceEntitlementRecord> activeEntitlements,
    required List<String> reasons,
  }) {
    if (expectedStatus == 'refunded' ||
        expectedStatus == 'canceled' ||
        expectedStatus == 'past_due') {
      if (activeEntitlements.isNotEmpty) {
        reasons.add('entitlements_should_be_revoked');
        return true;
      }
      return false;
    }

    MarketplaceEntitlementRecord? seatsEntitlement;
    MarketplaceEntitlementRecord? planEntitlement;
    for (final entitlement in activeEntitlements) {
      if (entitlement.entitlementType == 'seats') {
        seatsEntitlement = entitlement;
      }
      if (entitlement.entitlementType == 'plan') {
        planEntitlement = entitlement;
      }
    }
    if (seatsEntitlement == null) {
      reasons.add('missing_seats_entitlement');
      return true;
    }
    final grantedSeats =
        (seatsEntitlement.valueJson['seats_total'] as num?)?.toInt() ?? 0;
    if (grantedSeats != seatsTotal) {
      reasons.add('seats_entitlement_mismatch');
      return true;
    }
    if (planEntitlement == null) {
      reasons.add('missing_plan_entitlement');
      return true;
    }
    final currentPlan = (planEntitlement.valueJson['plan'] as String?) ?? '';
    if (currentPlan != offerId) {
      reasons.add('plan_entitlement_mismatch');
      return true;
    }
    return false;
  }
}
