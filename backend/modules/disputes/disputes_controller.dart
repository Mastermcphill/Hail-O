import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/services/dispute_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class DisputesController {
  DisputesController({required DisputeService disputeService, Uuid? uuid})
    : _disputeService = disputeService,
      _uuid = uuid ?? const Uuid();

  final DisputeService _disputeService;
  final Uuid _uuid;

  Router get router {
    final router = Router();
    router.post('/', _openDispute);
    router.post('/<disputeId>/resolve', _resolveDispute);
    return router;
  }

  Future<Response> _openDispute(Request request) async {
    _requireAuthenticated(request);
    final body = await readJsonBody(request);
    final rideId = (body['ride_id'] as String?)?.trim() ?? '';
    final reason = (body['reason'] as String?)?.trim() ?? '';
    if (rideId.isEmpty || reason.isEmpty) {
      throw const DomainInvariantError(code: 'ride_id_and_reason_required');
    }

    final result = await _disputeService.openDispute(
      disputeId: (body['dispute_id'] as String?)?.trim().isNotEmpty == true
          ? (body['dispute_id'] as String).trim()
          : _uuid.v4(),
      rideId: rideId,
      openedBy: request.requestContext.userId ?? '',
      reason: reason,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(201, result);
  }

  Future<Response> _resolveDispute(Request request, String disputeId) async {
    _requireAdmin(request);
    final body = await readJsonBody(request);
    final result = await _disputeService.resolveDispute(
      disputeId: disputeId,
      resolverUserId: request.requestContext.userId ?? '',
      resolverIsAdmin: true,
      refundMinor: (body['refund_minor'] as num?)?.toInt() ?? 0,
      resolutionNote: (body['resolution_note'] as String?) ?? 'resolved',
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  void _requireAuthenticated(Request request) {
    if ((request.requestContext.userId ?? '').isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
  }

  void _requireAdmin(Request request) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      throw const UnauthorizedActionError(code: 'admin_only');
    }
  }
}
