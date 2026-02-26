import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/dispatch_trip_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class DispatchController {
  DispatchController({required DispatchTripService dispatchTripService})
    : _dispatchTripService = dispatchTripService;

  final DispatchTripService _dispatchTripService;

  Router get router {
    final router = Router();
    router.post('/trips', _createTrip);
    router.get('/trips/<tripId>', _getTrip);
    router.get('/trips', _listTrips);
    router.post('/trips/<tripId>/status', _updateTripStatus);
    return router;
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
}
