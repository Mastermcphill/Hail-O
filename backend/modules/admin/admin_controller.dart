import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/wallet_reversal_service.dart';
import '../../infra/api_contract.dart';
import '../../infra/request_context.dart';
import '../marketplace/billing_ledger_repository.dart';
import '../marketplace/marketplace_entitlement_service.dart';
import '../marketplace/marketplace_reconciliation_service.dart';
import '../marketplace/marketplace_repository.dart';
import '../../server/http_utils.dart';

class AdminController {
  AdminController({
    required WalletReversalService walletReversalService,
    required Map<String, Object?> runtimeConfigSnapshot,
    required Map<String, Object?> buildInfo,
    MarketplaceRepository? marketplaceRepository,
    BillingLedgerRepository? billingLedgerRepository,
    MarketplaceEntitlementService? entitlementService,
    MarketplaceReconciliationService? reconciliationService,
  }) : _walletReversalService = walletReversalService,
       _runtimeConfigSnapshot = Map<String, Object?>.unmodifiable(
         runtimeConfigSnapshot,
       ),
       _buildInfo = Map<String, Object?>.unmodifiable(buildInfo),
       _marketplaceRepository = marketplaceRepository,
       _billingLedgerRepository = billingLedgerRepository,
       _entitlementService = entitlementService,
       _reconciliationService = reconciliationService;

  final WalletReversalService _walletReversalService;
  final Map<String, Object?> _runtimeConfigSnapshot;
  final Map<String, Object?> _buildInfo;
  final MarketplaceRepository? _marketplaceRepository;
  final BillingLedgerRepository? _billingLedgerRepository;
  final MarketplaceEntitlementService? _entitlementService;
  final MarketplaceReconciliationService? _reconciliationService;

  Router get router {
    final router = Router();
    router.get('/config', _runtimeConfig);
    router.get('/contract', _contract);
    router.post('/reversal', _reverseTransaction);
    router.get('/marketplace/purchases/<purchaseId>/debug', _marketplaceDebug);
    router.post(
      '/marketplace/purchases/<purchaseId>/reconcile',
      _marketplaceReconcile,
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

  Future<Response> _marketplaceDebug(Request request, String purchaseId) async {
    _requireAdmin(request);
    if (_marketplaceRepository == null ||
        _billingLedgerRepository == null ||
        _entitlementService == null ||
        _reconciliationService == null) {
      return jsonErrorResponse(
        request,
        501,
        code: 'marketplace_not_configured',
        message: 'Marketplace module is not configured',
      );
    }
    final purchase = await _marketplaceRepository.findPurchaseById(purchaseId);
    if (purchase == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'purchase_not_found',
        message: 'Marketplace purchase not found',
      );
    }
    final entitlements = await _entitlementService.listByPurchase(purchaseId);
    final ledgerEntries = await _billingLedgerRepository.listByPurchase(
      purchaseId,
    );
    final webhooks = await _marketplaceRepository.listWebhookEvents(purchaseId);
    final timeline = await _marketplaceRepository.listTimelineEvents(
      purchaseId,
      limit: 200,
    );
    final dryRun = await _reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      apply: false,
    );
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        'purchase': _jsonSafe(purchase),
        'entitlements': entitlements.map((row) => row.toMap()).toList(),
        'ledger_entries': ledgerEntries.map((row) => row.toMap()).toList(),
        'webhook_events': <String, Object?>{
          'total': webhooks.length,
          'processed': webhooks
              .where((event) => event['processed'] == true)
              .length,
          'items': _jsonSafe(webhooks),
        },
        'timeline': _jsonSafe(timeline),
        'reconciliation': dryRun?.toMap(),
      },
    });
  }

  Future<Response> _marketplaceReconcile(
    Request request,
    String purchaseId,
  ) async {
    _requireAdmin(request);
    if (_reconciliationService == null || _marketplaceRepository == null) {
      return jsonErrorResponse(
        request,
        501,
        code: 'marketplace_not_configured',
        message: 'Marketplace module is not configured',
      );
    }
    final before = await _marketplaceRepository.findPurchaseById(purchaseId);
    if (before == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'purchase_not_found',
        message: 'Marketplace purchase not found',
      );
    }
    final result = await _reconciliationService.reconcile(
      purchaseId: purchaseId,
      traceId: request.requestContext.traceId,
      apply: true,
    );
    if (result == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'purchase_not_found',
        message: 'Marketplace purchase not found',
      );
    }
    final after = await _marketplaceRepository.findPurchaseById(purchaseId);
    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'trace_id': request.requestContext.traceId,
      'data': <String, Object?>{
        'before': _jsonSafe(before),
        'after': _jsonSafe(after),
        'reconciliation': result.toMap(),
      },
    });
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
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
