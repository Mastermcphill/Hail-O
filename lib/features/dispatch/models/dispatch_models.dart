class DispatchLocation {
  const DispatchLocation({required this.lat, required this.lng, this.address});

  final double lat;
  final double lng;
  final String? address;

  factory DispatchLocation.fromMap(Map<String, dynamic> map) {
    return DispatchLocation(
      lat: _readDouble(map['lat']),
      lng: _readDouble(map['lng']),
      address: _readNullableString(map['address']),
    );
  }
}

class DispatchQuote {
  const DispatchQuote({
    required this.distanceKm,
    required this.durationMinEst,
    required this.priceMinor,
    required this.currency,
    required this.breakdown,
  });

  final double distanceKm;
  final int durationMinEst;
  final int priceMinor;
  final String currency;
  final Map<String, dynamic> breakdown;

  factory DispatchQuote.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    return DispatchQuote(
      distanceKm: _readDouble(payload['distance_km']),
      durationMinEst: _readInt(payload['duration_min_est']),
      priceMinor: _readInt(payload['price_minor']),
      currency: _readString(payload['currency'], fallback: 'NGN'),
      breakdown: _readMap(payload['breakdown']),
    );
  }
}

class DispatchTrip {
  const DispatchTrip({
    required this.id,
    required this.userId,
    required this.status,
    required this.pickup,
    required this.dropoff,
    this.notes,
    this.scheduledAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String status;
  final DispatchLocation pickup;
  final DispatchLocation dropoff;
  final String? notes;
  final String? scheduledAt;
  final String? createdAt;
  final String? updatedAt;

  factory DispatchTrip.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    final trip = _readMap(payload['trip']).isEmpty
        ? payload
        : _readMap(payload['trip']);
    return DispatchTrip(
      id: _readString(trip['id']),
      userId: _readString(trip['user_id']),
      status: _readString(trip['status']),
      pickup: DispatchLocation.fromMap(_readMap(trip['pickup'])),
      dropoff: DispatchLocation.fromMap(_readMap(trip['dropoff'])),
      notes: _readNullableString(trip['notes']),
      scheduledAt: _readNullableString(trip['scheduled_at']),
      createdAt: _readNullableString(trip['created_at']),
      updatedAt: _readNullableString(trip['updated_at']),
    );
  }
}

class DispatchStatusEvent {
  const DispatchStatusEvent({
    required this.toStatus,
    this.id,
    this.fromStatus,
    this.actorUserId,
    this.createdAt,
    this.metadata = const <String, dynamic>{},
  });

  final String? id;
  final String? fromStatus;
  final String toStatus;
  final String? actorUserId;
  final String? createdAt;
  final Map<String, dynamic> metadata;

  factory DispatchStatusEvent.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    final event = _readMap(payload['event']).isEmpty
        ? payload
        : _readMap(payload['event']);
    return DispatchStatusEvent(
      id: _readNullableString(event['id']),
      fromStatus: _readNullableString(event['from_status']),
      toStatus: _readString(event['to_status']),
      actorUserId: _readNullableString(event['actor_user_id']),
      createdAt: _readNullableString(event['created_at']),
      metadata: _readMap(event['metadata']),
    );
  }
}

class DispatchStatusUpdateResult {
  const DispatchStatusUpdateResult({required this.trip, required this.event});

  final DispatchTrip trip;
  final DispatchStatusEvent event;
}

class DispatchTripPage {
  const DispatchTripPage({required this.trips, this.nextCursor});

  final List<DispatchTrip> trips;
  final String? nextCursor;

  factory DispatchTripPage.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    final rawTrips = payload['trips'];
    final trips = rawTrips is List
        ? rawTrips
              .whereType<Map>()
              .map(
                (entry) => DispatchTrip.fromMap(
                  entry.map(
                    (key, value) =>
                        MapEntry<String, dynamic>(key.toString(), value),
                  ),
                ),
              )
              .toList(growable: false)
        : const <DispatchTrip>[];
    return DispatchTripPage(
      trips: trips,
      nextCursor: _readNullableString(payload['next_cursor']),
    );
  }
}

class DispatchAssignment {
  const DispatchAssignment({
    required this.id,
    required this.tripId,
    required this.driverId,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tripId;
  final String driverId;
  final String status;
  final String? createdAt;
  final String? updatedAt;

  factory DispatchAssignment.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    final assignment = _readMap(payload['assignment']).isEmpty
        ? payload
        : _readMap(payload['assignment']);
    return DispatchAssignment(
      id: _readString(assignment['id']),
      tripId: _readString(assignment['trip_id']),
      driverId: _readString(assignment['driver_id']),
      status: _readString(assignment['status']),
      createdAt: _readNullableString(assignment['created_at']),
      updatedAt: _readNullableString(assignment['updated_at']),
    );
  }
}

class DispatchAssignmentResult {
  const DispatchAssignmentResult({
    required this.trip,
    required this.assignment,
  });

  final DispatchTrip trip;
  final DispatchAssignment assignment;
}

class DispatchNearbyDriver {
  const DispatchNearbyDriver({
    required this.driverId,
    required this.status,
    required this.safetyScore,
    required this.starRating,
    this.displayName,
  });

  final String driverId;
  final String status;
  final int safetyScore;
  final double starRating;
  final String? displayName;

  factory DispatchNearbyDriver.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    return DispatchNearbyDriver(
      driverId: _readString(payload['driver_id']),
      status: _readString(payload['status'], fallback: 'active'),
      safetyScore: _readInt(payload['safety_score']),
      starRating: _readDouble(payload['star_rating']),
      displayName: _readNullableString(payload['display_name']),
    );
  }
}

class DispatchNearbyDriversPage {
  const DispatchNearbyDriversPage({required this.drivers});

  final List<DispatchNearbyDriver> drivers;

  factory DispatchNearbyDriversPage.fromMap(Map<String, dynamic> map) {
    final payload = _unwrapEnvelope(map);
    final rawDrivers = payload['drivers'];
    final drivers = rawDrivers is List
        ? rawDrivers
              .whereType<Map>()
              .map(
                (entry) => DispatchNearbyDriver.fromMap(
                  entry.map(
                    (key, value) =>
                        MapEntry<String, dynamic>(key.toString(), value),
                  ),
                ),
              )
              .toList(growable: false)
        : const <DispatchNearbyDriver>[];
    return DispatchNearbyDriversPage(drivers: drivers);
  }
}

Map<String, dynamic> _unwrapEnvelope(Map<String, dynamic> map) {
  final data = map['data'];
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  return map;
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, nestedValue) {
      return MapEntry<String, dynamic>(key.toString(), nestedValue);
    });
  }
  return <String, dynamic>{};
}

String _readString(Object? value, {String fallback = ''}) {
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return fallback;
}

String? _readNullableString(Object? value) {
  final normalized = _readString(value);
  return normalized.isEmpty ? null : normalized;
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double _readDouble(Object? value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}
