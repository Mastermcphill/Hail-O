class DriverProfile {
  const DriverProfile({
    required this.driverId,
    required this.cashDebtMinor,
    required this.safetyScore,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.fleetOwnerId,
  });

  final String driverId;
  final String? fleetOwnerId;
  final int cashDebtMinor;
  final int safetyScore;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'driver_id': driverId,
      'fleet_owner_id': fleetOwnerId,
      'cash_debt_minor': cashDebtMinor,
      'safety_score': safetyScore,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory DriverProfile.fromMap(Map<String, Object?> map) {
    return DriverProfile(
      driverId: map['driver_id'] as String,
      fleetOwnerId: map['fleet_owner_id'] as String?,
      cashDebtMinor: (map['cash_debt_minor'] as num?)?.toInt() ?? 0,
      safetyScore: (map['safety_score'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
