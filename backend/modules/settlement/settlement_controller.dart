import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/escrow_service.dart';
import '../../../lib/domain/services/ride_settlement_service.dart';
import '../../../lib/services/payout_autosave_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class SettlementController {
  SettlementController({
    required RideSettlementService rideSettlementService,
    required EscrowService escrowService,
    required PayoutAutosaveService payoutAutosaveService,
  }) : _rideSettlementService = rideSettlementService,
       _escrowService = escrowService,
       _payoutAutosaveService = payoutAutosaveService;

  final RideSettlementService _rideSettlementService;
  final EscrowService _escrowService;
  final PayoutAutosaveService _payoutAutosaveService;

  Router get router {
    final router = Router();
    router.get('/autosave/status', _autosaveStatus);
    router.post('/autosave/configure', _configureAutosave);
    router.post('/autosave/disable', _disableAutosave);
    router.get('/autosave/ledger', _autosaveLedger);
    router.post('/run', _runSettlement);
    router.post('/release/manual', _releaseManual);
    return router;
  }

  Future<Response> _autosaveStatus(Request request) async {
    _requireRole(request, const <String>{'driver'});
    final userId = _requireUserId(request);
    final payload = await _payoutAutosaveService.getStatus(userId: userId);
    return jsonResponse(200, payload);
  }

  Future<Response> _configureAutosave(Request request) async {
    _requireRole(request, const <String>{'driver'});
    final userId = _requireUserId(request);
    final body = await readJsonBody(request);
    final mainBank = _parseBank(
      body['main_bank'],
      missingCode: 'main_bank_required',
    );
    final savingsBank = _parseBank(
      body['savings_bank'],
      missingCode: 'savings_bank_required',
    );
    final payload = await _payoutAutosaveService.configurePlan(
      userId: userId,
      autosaveEnabled: (body['autosave_enabled'] as bool?) ?? true,
      tier: (body['tier'] as num?)?.toInt() ?? 1,
      autosavePercent: (body['autosave_percent'] as num?)?.toInt() ?? 5,
      mainBank: mainBank,
      savingsBank: savingsBank,
      idempotencyKey: request.requestContext.idempotencyKey,
    );
    return jsonResponse(200, payload);
  }

  Future<Response> _disableAutosave(Request request) async {
    _requireRole(request, const <String>{'driver'});
    final userId = _requireUserId(request);
    final body = await readJsonBody(request);
    final payload = await _payoutAutosaveService.disablePlan(
      userId: userId,
      reason: (body['reason'] as String?)?.trim() ?? '',
      idempotencyKey: request.requestContext.idempotencyKey,
    );
    return jsonResponse(200, payload);
  }

  Future<Response> _autosaveLedger(Request request) async {
    _requireRole(request, const <String>{'driver'});
    final userId = _requireUserId(request);
    final limit =
        int.tryParse((request.url.queryParameters['limit'] ?? '50').trim()) ??
        50;
    final ledger = await _payoutAutosaveService.listLedger(
      userId: userId,
      limit: limit,
    );
    return jsonResponse(200, <String, Object?>{'ok': true, 'ledger': ledger});
  }

  Future<Response> _runSettlement(Request request) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);
    final rideId = (body['ride_id'] as String?)?.trim() ?? '';
    final escrowId = (body['escrow_id'] as String?)?.trim() ?? '';
    if (rideId.isEmpty || escrowId.isEmpty) {
      throw const DomainInvariantError(code: 'ride_id_and_escrow_id_required');
    }

    final settlement = await _rideSettlementService.settleOnEscrowRelease(
      rideId: rideId,
      escrowId: escrowId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      trigger: SettlementTrigger.fromDbValue(
        (body['trigger'] as String?) ?? 'manual_override',
      ),
    );
    return jsonResponse(200, settlement.toMap());
  }

  Future<Response> _releaseManual(Request request) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final body = await readJsonBody(request);

    final escrowId = (body['escrow_id'] as String?)?.trim() ?? '';
    if (escrowId.isEmpty) {
      throw const DomainInvariantError(code: 'escrow_id_required');
    }

    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    final defaultRiderId = request.requestContext.userId ?? '';
    final riderId = role == 'admin'
        ? ((body['rider_id'] as String?)?.trim() ?? defaultRiderId)
        : defaultRiderId;
    if (riderId.isEmpty) {
      throw const DomainInvariantError(code: 'rider_id_required');
    }

    final result = await _escrowService.releaseOnManualOverride(
      escrowId: escrowId,
      riderId: riderId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      settlementIdempotencyKey: (body['settlement_idempotency_key'] as String?)
          ?.trim(),
    );
    return jsonResponse(200, result);
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }

  void _requireRole(Request request, Set<String> allowedRoles) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (!allowedRoles.contains(role)) {
      throw const UnauthorizedActionError(code: 'forbidden');
    }
  }

  String _requireUserId(Request request) {
    final userId = (request.requestContext.userId ?? '').trim();
    if (userId.isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
    return userId;
  }

  AutosaveBankDestination _parseBank(
    Object? raw, {
    required String missingCode,
  }) {
    if (raw is! Map) {
      throw DomainInvariantError(code: missingCode);
    }
    final map = raw.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
    final accountNumber = (map['account_number'] as String?)?.trim() ?? '';
    final bankCode = (map['bank_code'] as String?)?.trim() ?? '';
    final name = (map['name'] as String?)?.trim() ?? '';
    if (accountNumber.isEmpty || bankCode.isEmpty || name.isEmpty) {
      throw DomainInvariantError(code: missingCode);
    }
    return AutosaveBankDestination(
      accountNumber: accountNumber,
      bankCode: bankCode,
      name: name,
    );
  }
}
