import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/wallet_reversal_service.dart';
import '../../infra/api_contract.dart';
import '../../infra/request_context.dart';
import '../marketplace/billing_ledger_repository.dart';
import '../marketplace/marketplace_entitlement_service.dart';
import '../marketplace/marketplace_offer_repository.dart';
import '../marketplace/marketplace_reconciliation_service.dart';
import '../../server/http_utils.dart';

class AdminController {
  AdminController({
    required WalletReversalService walletReversalService,
    required Map<String, Object?> runtimeConfigSnapshot,
    required Map<String, Object?> buildInfo,
    MarketplaceReconciliationService? reconciliationService,
  }) : _walletReversalService = walletReversalService,
       _runtimeConfigSnapshot = Map<String, Object?>.unmodifiable(
         runtimeConfigSnapshot,
       ),
       _buildInfo = Map<String, Object?>.unmodifiable(buildInfo),
       _reconciliationService = reconciliationService;

  final WalletReversalService _walletReversalService;
  final Map<String, Object?> _runtimeConfigSnapshot;
  final Map<String, Object?> _buildInfo;
  final MarketplaceReconciliationService? _reconciliationService;

  Router get router {
    final router = Router();
    router.get('/config', _runtimeConfig);
    router.get('/contract', _contract);
    router.post('/reversal', _reverseTransaction);
    router.get(
      '/marketplace/purchases/<purchaseId>/debug',
      _marketplacePurchaseDebug,
    );
    router.post(
      '/marketplace/purchases/<purchaseId>/reconcile',
      _marketplacePurchaseReconcile,
    );
    return router;
  }

  Future<Response> _runtimeConfig(Request request) async {
    _requireAdmin(request);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'config': _runtimeConfigSnapshot,
    });
  }

  Future<Response> _contract(Request request) async {
    _requireAdmin(request);
    return jsonResponse(200, buildAdminContractPayload(buildInfo: _buildInfo));
  }

  Future<Response> _reverseTransaction(Request request) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);

    final originalLedgerId = (body['original_ledger_id'] as num?)?.toInt();
    if (originalLedgerId == null || originalLedgerId <= 0) {
      throw const DomainInvariantError(code: 'original_ledger_id_required');
    }

    final result = await _walletReversalService.reverseWalletLedgerEntry(
      originalLedgerId: originalLedgerId,
      requestedByUserId: request.requestContext.userId ?? '',
      requesterIsAdmin: true,
      reason: (body['reason'] as String?)?.trim().isNotEmpty == true
          ? (body['reason'] as String).trim()
          : 'admin_reversal',
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      reversalAmountMinor: (body['reversal_amount_minor'] as num?)?.toInt(),
    );
    return jsonResponse(200, result);
  }

  Future<Response> _marketplacePurchaseDebug(
    Request request,
    String purchaseId,
  ) async {
    _requireAdmin(request);
    final reconciliationService = _reconciliationService;
    if (reconciliationService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Marketplace reconciliation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final result = await reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      dryRun: true,
    );
    if (result == null) {
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'Marketplace purchase not found',
        'trace_id': request.requestContext.traceId,
      });
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'data': <String, Object?>{
        'purchase': _purchasePayload(result.purchase),
        'latest_entitlements': result.entitlementsBefore
            .map(_entitlementPayload)
            .toList(growable: false),
        'ledger_entries': result.ledgerEntries
            .map(_ledgerPayload)
            .toList(growable: false),
        'webhook_events_summary': result.webhookEvents
            .map(_webhookPayload)
            .toList(growable: false),
        'timeline': result.timelineEvents
            .map(_timelinePayload)
            .toList(growable: false),
        'reconciliation_dry_run': <String, Object?>{
          'drift_detected': result.driftDetected,
          'would_apply': result.driftDetected,
          'current_status': result.currentStatus,
          'expected_status': result.expectedStatus,
          'drift_reasons': result.driftReasons,
        },
      },
      'trace_id': request.requestContext.traceId,
    });
  }

  Future<Response> _marketplacePurchaseReconcile(
    Request request,
    String purchaseId,
  ) async {
    _requireAdmin(request);
    final reconciliationService = _reconciliationService;
    if (reconciliationService == null) {
      return jsonResponse(501, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_IMPLEMENTED',
        'message': 'Marketplace reconciliation is unavailable in this mode',
        'trace_id': request.requestContext.traceId,
      });
    }
    final result = await reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      dryRun: false,
    );
    if (result == null) {
      return jsonResponse(404, <String, Object?>{
        'ok': false,
        'error_code': 'NOT_FOUND',
        'message': 'Marketplace purchase not found',
        'trace_id': request.requestContext.traceId,
      });
    }

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'data': <String, Object?>{
        'purchase_id': result.purchaseId,
        'before': <String, Object?>{'status': result.currentStatus},
        'after': <String, Object?>{'status': result.finalStatus},
        'applied': result.applied,
        'drift_detected': result.driftDetected,
        'drift_reasons': result.driftReasons,
      },
      'trace_id': request.requestContext.traceId,
    });
  }

  Map<String, Object?> _purchasePayload(MarketplacePurchaseRecord purchase) {
    return <String, Object?>{
      'id': purchase.id,
      'user_id': purchase.userId,
      'offer_id': purchase.offerId,
      'offer_title': purchase.offerTitle,
      'status': purchase.status,
      'currency': purchase.currency,
      'price_minor': purchase.totalAmountMinor,
      'seats_total': purchase.seatCount,
      'idempotency_key': purchase.idempotencyKey,
      'created_at': purchase.createdAt.toIso8601String(),
      'updated_at': purchase.updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _entitlementPayload(MarketplaceEntitlementRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'user_id': row.userId,
      'entitlement_type': row.entitlementType,
      'value_json': row.value,
      'status': row.status,
      'effective_from': row.effectiveFrom.toIso8601String(),
      'effective_to': row.effectiveTo?.toIso8601String(),
    };
  }

  Map<String, Object?> _ledgerPayload(BillingLedgerEntryRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'user_id': row.userId,
      'entry_type': row.entryType,
      'provider': row.provider,
      'provider_ref': row.providerRef,
      'amount_minor': row.amountMinor,
      'currency': row.currency,
      'metadata': row.metadata,
      'occurred_at': row.occurredAt.toIso8601String(),
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _webhookPayload(MarketplaceWebhookEventSummary row) {
    return <String, Object?>{
      'provider': row.provider,
      'provider_event_id': row.providerEventId,
      'event_type': row.eventType,
      'signature_valid': row.signatureValid,
      'processed': row.processed,
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _timelinePayload(MarketplaceTimelineEventRecord row) {
    return <String, Object?>{
      'id': row.id,
      'purchase_id': row.purchaseId,
      'event_type': row.eventType,
      'event_data': row.eventData,
      'created_at': row.createdAt.toIso8601String(),
    };
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }
}
