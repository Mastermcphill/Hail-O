import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/dispatch_pricing_service.dart';
import '../../../lib/domain/services/dispatch_trip_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class DispatchController {
  DispatchController({
    required DispatchTripService dispatchTripService,
    required DispatchPricingService dispatchPricingService,
  }) : _dispatchTripService = dispatchTripService,
       _dispatchPricingService = dispatchPricingService;

  final DispatchTripService _dispatchTripService;
  final DispatchPricingService _dispatchPricingService;

  Router get router {
    final router = Router();
    router.post('/quote', _quote);
    router.post('/trips', _createTrip);
    router.get('/trips/<tripId>', _getTrip);
    router.get('/trips', _listTrips);
    router.post('/trips/<tripId>/status', _updateTripStatus);
    router.post('/trips/<tripId>/assign', _assignDriver);
    router.get('/drivers/nearby', _nearbyDrivers);
    return router;
  }

  Future<Response> _quote(Request request) async {
    _requireUserId(request);
    final payload = await readJsonBody(request);
    final quote = _dispatchPricingService.quoteFromPayload(payload);
    return jsonResponse(200, <String, Object?>{'ok': true, ...quote});
  }

  Future<Response> _createTrip(Request request) async {
    final userId = _requireUserId(request);
    final payload = await readJsonBody(request);
    final created = await _dispatchTripService.createTrip(
      userId: userId,
      payload: payload,
    );
    return jsonResponse(201, <String, Object?>{'ok': true, ...created});
  }

  Future<Response> _getTrip(Request request, String tripId) async {
    final userId = _requireUserId(request);
    final trip = await _dispatchTripService.getTrip(
      tripId: tripId.trim(),
      requesterUserId: userId,
      requesterIsAdmin: _isAdmin(request),
    );
    return jsonResponse(200, <String, Object?>{'ok': true, 'trip': trip});
  }

  Future<Response> _listTrips(Request request) async {
    final userId = _requireUserId(request);
    final limit = _parseLimit(request.url.queryParameters['limit']);
    final status = request.url.queryParameters['status'];
    final cursor = request.url.queryParameters['cursor'];
    final listed = await _dispatchTripService.listTrips(
      requesterUserId: userId,
      status: status,
      limit: limit,
      cursor: cursor,
    );
    return jsonResponse(200, <String, Object?>{'ok': true, ...listed});
  }

  Future<Response> _updateTripStatus(Request request, String tripId) async {
    final actorUserId = _requireUserId(request);
    final payload = await readJsonBody(request);
    final updated = await _dispatchTripService.transitionStatus(
      tripId: tripId.trim(),
      actorUserId: actorUserId,
      actorIsAdmin: _isAdmin(request),
      payload: payload,
    );
    return jsonResponse(200, <String, Object?>{'ok': true, ...updated});
  }

  Future<Response> _assignDriver(Request request, String tripId) async {
    final actorUserId = _requireUserId(request);
    final payload = await readJsonBody(request);
    try {
      final assigned = await _dispatchTripService.assignDriver(
        tripId: tripId.trim(),
        actorUserId: actorUserId,
        actorIsAdmin: _isAdmin(request),
        payload: payload,
      );
      return jsonResponse(200, <String, Object?>{'ok': true, ...assigned});
    } on DispatchNotFoundError catch (error) {
      return jsonErrorResponse(
        request,
        404,
        code: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> _nearbyDrivers(Request request) async {
    _requireUserId(request);
    _parseCoordinate(request.url.queryParameters['lat'], min: -90, max: 90);
    _parseCoordinate(request.url.queryParameters['lng'], min: -180, max: 180);
    _parseRadiusKm(request.url.queryParameters['radius_km']);
    final limit = _parseLimit(request.url.queryParameters['limit']);
    final listed = await _dispatchTripService.listNearbyDrivers(limit: limit);
    return jsonResponse(200, <String, Object?>{'ok': true, ...listed});
  }

  String _requireUserId(Request request) {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
    return userId;
  }

  bool _isAdmin(Request request) {
    final role = request.requestContext.role?.trim().toLowerCase() ?? '';
    return role == 'admin';
  }

  int _parseLimit(String? rawLimit) {
    final normalized = rawLimit?.trim() ?? '';
    if (normalized.isEmpty) {
      return 20;
    }
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed <= 0) {
      throw const DomainInvariantError(code: 'invalid_limit');
    }
    return parsed > 100 ? 100 : parsed;
  }

  double _parseCoordinate(
    String? rawValue, {
    required double min,
    required double max,
  }) {
    final normalized = rawValue?.trim() ?? '';
    if (normalized.isEmpty) {
      throw const DomainInvariantError(code: 'coordinate_required');
    }
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value.isInfinite) {
      throw const DomainInvariantError(code: 'invalid_coordinate');
    }
    if (value < min || value > max) {
      throw const DomainInvariantError(code: 'invalid_coordinate');
    }
    return value;
  }

  double _parseRadiusKm(String? rawRadiusKm) {
    final normalized = rawRadiusKm?.trim() ?? '';
    if (normalized.isEmpty) {
      return 5;
    }
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value.isInfinite || value <= 0) {
      throw const DomainInvariantError(code: 'invalid_radius_km');
    }
    if (value > 500) {
      throw const DomainInvariantError(code: 'invalid_radius_km');
    }
    return value;
  }
}
