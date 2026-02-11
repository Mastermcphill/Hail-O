class ManifestEntry {
  const ManifestEntry({
    required this.id,
    required this.rideId,
    required this.riderId,
    required this.status,
    required this.nextOfKinValid,
    required this.docValid,
    required this.createdAt,
    required this.updatedAt,
    this.seatId,
  });

  final String id;
  final String rideId;
  final String riderId;
  final String? seatId;
  final String status;
  final bool nextOfKinValid;
  final bool docValid;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'rider_id': riderId,
      'seat_id': seatId,
      'status': status,
      'no_kin_valid': nextOfKinValid ? 1 : 0,
      'doc_valid': docValid ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ManifestEntry.fromMap(Map<String, Object?> map) {
    return ManifestEntry(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      riderId: map['rider_id'] as String,
      seatId: map['seat_id'] as String?,
      status: map['status'] as String,
      nextOfKinValid: ((map['no_kin_valid'] as num?)?.toInt() ?? 0) == 1,
      docValid: ((map['doc_valid'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
