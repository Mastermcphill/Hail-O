enum VehicleType {
  sedan('sedan'),
  hatchback('hatchback'),
  suv('suv'),
  bus('bus');

  const VehicleType(this.dbValue);

  final String dbValue;

  static VehicleType fromDbValue(String value) {
    return VehicleType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => VehicleType.sedan,
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.driverId,
    required this.type,
    required this.seatCount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.plateNumber,
  });

  final String id;
  final String driverId;
  final VehicleType type;
  final String? plateNumber;
  final int seatCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'driver_id': driverId,
      'type': type.dbValue,
      'plate_number': plateNumber,
      'seat_count': seatCount,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Vehicle.fromMap(Map<String, Object?> map) {
    return Vehicle(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      type: VehicleType.fromDbValue(map['type'] as String),
      plateNumber: map['plate_number'] as String?,
      seatCount: (map['seat_count'] as num?)?.toInt() ?? 4,
      isActive: ((map['is_active'] as num?)?.toInt() ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
