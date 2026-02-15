import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/ride_api_flow_service.dart';
import '../../../lib/domain/services/ride_settlement_service.dart';
import '../../../lib/domain/services/ride_snapshot_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class RidesController {
  RidesController({
    required RideApiFlowService rideApiFlowService,
    required RideSnapshotService rideSnapshotService,
  }) : _rideApiFlowService = rideApiFlowService,
       _rideSnapshotService = rideSnapshotService;

  final RideApiFlowService _rideApiFlowService;
  final RideSnapshotService _rideSnapshotService;

  Router get router {
    final router = Router();
    router.post('/request', _requestRide);
    router.post('/<rideId>/accept', _acceptRide);
    router.post('/<rideId>/cancel', _cancelRide);
    router.post('/<rideId>/complete', _completeRide);
    router.get('/<rideId>', _getRideSnapshot);
    return router;
  }

  Future<Response> _requestRide(Request request) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final body = await readJsonBody(request);
    final riderId = request.requestContext.userId ?? '';
    if (riderId.isEmpty) {
      throw const UnauthorizedActionError(code: 'missing_user_context');
    }

    final scheduledRaw = (body['scheduled_departure_at'] as String?)?.trim();
    if (scheduledRaw == null || scheduledRaw.isEmpty) {
      throw const DomainInvariantError(code: 'scheduled_departure_required');
    }
    final scheduledDeparture = DateTime.parse(scheduledRaw).toUtc();

    final tripScope = _tripScopeFromRaw(
      (body['trip_scope'] as String?) ?? ApiTripScope.intraCity.dbValue,
    );

    final result = await _rideApiFlowService.requestRide(
      riderUserId: riderId,
      tripScope: tripScope,
      scheduledDepartureAtUtc: scheduledDeparture,
      distanceMeters: (body['distance_meters'] as num?)?.toInt() ?? 0,
      durationSeconds: (body['duration_seconds'] as num?)?.toInt() ?? 0,
      luggageCount: (body['luggage_count'] as num?)?.toInt() ?? 0,
      vehicleClass:
          (body['vehicle_class'] as String?)?.trim().toLowerCase() ?? 'sedan',
      baseFareMinor: (body['base_fare_minor'] as num?)?.toInt() ?? 0,
      premiumMarkupMinor: (body['premium_markup_minor'] as num?)?.toInt() ?? 0,
      connectionFeeMinor: (body['connection_fee_minor'] as num?)?.toInt() ?? 0,
      rideId: (body['ride_id'] as String?)?.trim(),
      idempotencyKey: request.requestContext.idempotencyKey,
    );

    return jsonResponse(201, result);
  }

  Future<Response> _acceptRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final body = await readJsonBody(request);
    final userRole = request.requestContext.role ?? '';
    final ctxUserId = request.requestContext.userId ?? '';
    final driverId = userRole == 'admin'
        ? ((body['driver_id'] as String?)?.trim() ?? '')
        : ctxUserId;
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'driver_id_required');
    }

    final result = await _rideApiFlowService.acceptRide(
      rideId: rideId,
      driverId: driverId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  Future<Response> _cancelRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'driver', 'admin'});
    final actorId = request.requestContext.userId ?? '';
    if (actorId.isEmpty) {
      throw const UnauthorizedActionError(code: 'missing_user_context');
    }

    final result = await _rideApiFlowService.cancelRide(
      rideId: rideId,
      actorUserId: actorId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  Future<Response> _completeRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final body = await readJsonBody(request);

    final settlementTrigger = SettlementTrigger.fromDbValue(
      (body['settlement_trigger'] as String?) ?? 'manual_override',
    );
    final result = await _rideApiFlowService.completeAndSettleRide(
      rideId: rideId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      escrowId: (body['escrow_id'] as String?)?.trim(),
      trigger: settlementTrigger,
    );
    return jsonResponse(200, result);
  }

  Future<Response> _getRideSnapshot(Request request, String rideId) async {
    _requireAuthenticated(request);
    final snapshot = await _rideSnapshotService.getRideSnapshot(rideId);
    if (snapshot['ok'] != true) {
      return jsonResponse(404, snapshot);
    }
    return jsonResponse(200, snapshot);
  }

  ApiTripScope _tripScopeFromRaw(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final scope in ApiTripScope.values) {
      if (scope.dbValue == normalized) {
        return scope;
      }
    }
    return ApiTripScope.intraCity;
  }

  void _requireAuthenticated(Request request) {
    if ((request.requestContext.userId ?? '').isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
  }

  void _requireRole(Request request, Set<String> allowedRoles) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (!allowedRoles.contains(role)) {
      throw const UnauthorizedActionError(code: 'forbidden');
    }
  }
}
