import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/escrow_service.dart';
import '../../../lib/domain/services/ride_settlement_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class SettlementController {
  SettlementController({
    required RideSettlementService rideSettlementService,
    required EscrowService escrowService,
  }) : _rideSettlementService = rideSettlementService,
       _escrowService = escrowService;

  final RideSettlementService _rideSettlementService;
  final EscrowService _escrowService;

  Router get router {
    final router = Router();
    router.post('/run', _runSettlement);
    router.post('/release/manual', _releaseManual);
    return router;
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
}
