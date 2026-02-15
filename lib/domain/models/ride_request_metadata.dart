class RideRequestMetadata {
  const RideRequestMetadata({
    required this.rideId,
    required this.scheduledDepartureAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String rideId;
  final DateTime scheduledDepartureAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ride_id': rideId,
      'scheduled_departure_at': scheduledDepartureAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory RideRequestMetadata.fromMap(Map<String, Object?> map) {
    return RideRequestMetadata(
      rideId: map['ride_id'] as String,
      scheduledDepartureAt: DateTime.parse(
        map['scheduled_departure_at'] as String,
      ).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
