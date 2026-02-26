import '../../../core/api/api_client.dart';
import '../../../core/api/api_paths.dart';
import '../models/dispatch_models.dart';

class DispatchRepository {
  DispatchRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<DispatchQuote> createQuote({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String serviceLevel = 'standard',
  }) async {
    final response = await _apiClient.post(
      ApiPaths.dispatchQuote,
      body: <String, dynamic>{
        'pickup': <String, dynamic>{'lat': pickupLat, 'lng': pickupLng},
        'dropoff': <String, dynamic>{'lat': dropoffLat, 'lng': dropoffLng},
        'service_level': serviceLevel,
      },
    );
    return DispatchQuote.fromMap(response);
  }

  Future<DispatchTrip> createTrip({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
    String? notes,
  }) async {
    final response = await _apiClient.post(
      ApiPaths.dispatchTrips,
      body: <String, dynamic>{
        'pickup': <String, dynamic>{
          'lat': pickupLat,
          'lng': pickupLng,
          if ((pickupAddress ?? '').trim().isNotEmpty)
            'address': pickupAddress!.trim(),
        },
        'dropoff': <String, dynamic>{
          'lat': dropoffLat,
          'lng': dropoffLng,
          if ((dropoffAddress ?? '').trim().isNotEmpty)
            'address': dropoffAddress!.trim(),
        },
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      },
    );
    return DispatchTrip.fromMap(response);
  }

  Future<DispatchTripPage> listTrips({
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if ((status ?? '').trim().isNotEmpty) {
      query['status'] = status!.trim();
    }
    if ((cursor ?? '').trim().isNotEmpty) {
      query['cursor'] = cursor!.trim();
    }
    final path = Uri(
      path: ApiPaths.dispatchTrips,
      queryParameters: query,
    ).toString();
    final response = await _apiClient.get(path);
    return DispatchTripPage.fromMap(response);
  }

  Future<DispatchTrip> getTrip(String tripId) async {
    final response = await _apiClient.get(ApiPaths.dispatchTrip(tripId.trim()));
    return DispatchTrip.fromMap(response);
  }

  Future<DispatchStatusUpdateResult> updateStatus({
    required String tripId,
    required String status,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _apiClient.post(
      ApiPaths.dispatchTripStatus(tripId.trim()),
      body: <String, dynamic>{
        'status': status.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
    );
    return DispatchStatusUpdateResult(
      trip: DispatchTrip.fromMap(response),
      event: DispatchStatusEvent.fromMap(response),
    );
  }

  Future<DispatchAssignmentResult> assignDriver({
    required String tripId,
    required String driverId,
  }) async {
    final response = await _apiClient.post(
      ApiPaths.dispatchTripAssign(tripId.trim()),
      body: <String, dynamic>{'driver_id': driverId.trim()},
    );
    return DispatchAssignmentResult(
      trip: DispatchTrip.fromMap(response),
      assignment: DispatchAssignment.fromMap(response),
    );
  }

  Future<DispatchNearbyDriversPage> listNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 5,
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      ApiPaths.dispatchNearbyDrivers(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        limit: limit,
      ),
    );
    return DispatchNearbyDriversPage.fromMap(response);
  }
}
