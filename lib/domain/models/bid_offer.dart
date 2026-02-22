class BidOffer {
  const BidOffer({
    required this.id,
    required this.rideId,
    required this.riderId,
    required this.driverId,
    required this.offeredFareMinor,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.acceptedAt,
  });

  final String id;
  final String rideId;
  final String riderId;
  final String driverId;
  final int offeredFareMinor;
  final String status;
  final DateTime? acceptedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'rider_id': riderId,
      'driver_id': driverId,
      'offered_fare_minor': offeredFareMinor,
      'status': status,
      'accepted_at': acceptedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory BidOffer.fromMap(Map<String, Object?> map) {
    final acceptedAt = map['accepted_at'] as String?;
    return BidOffer(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      riderId: map['rider_id'] as String,
      driverId: map['driver_id'] as String,
      offeredFareMinor: (map['offered_fare_minor'] as num?)?.toInt() ?? 0,
      status: map['status'] as String,
      acceptedAt: acceptedAt == null
          ? null
          : DateTime.parse(acceptedAt).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
