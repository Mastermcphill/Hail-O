import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/ride_settlement_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class SettlementController {
  SettlementController({required RideSettlementService rideSettlementService})
    : _rideSettlementService = rideSettlementService;

  final RideSettlementService _rideSettlementService;

  Router get router {
    final router = Router();
    router.post('/run', _runSettlement);
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

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }
}
