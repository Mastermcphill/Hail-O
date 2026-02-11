enum SeatCode {
  frontRight('front_right'),
  backLeft('back_left'),
  backMiddle('back_middle'),
  backRight('back_right');

  const SeatCode(this.dbValue);

  final String dbValue;

  static SeatCode fromDbValue(String value) {
    return SeatCode.values.firstWhere(
      (code) => code.dbValue == value,
      orElse: () => SeatCode.backLeft,
    );
  }
}

enum SeatType {
  front('front'),
  window('window'),
  middle('middle');

  const SeatType(this.dbValue);

  final String dbValue;

  static SeatType fromDbValue(String value) {
    return SeatType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => SeatType.middle,
    );
  }
}

class Seat {
  const Seat({
    required this.id,
    required this.rideId,
    required this.seatCode,
    required this.seatType,
    required this.baseFareMinor,
    required this.markupMinor,
    required this.assignmentLocked,
    required this.createdAt,
    required this.updatedAt,
    this.passengerUserId,
  });

  final String id;
  final String rideId;
  final SeatCode seatCode;
  final SeatType seatType;
  final int baseFareMinor;
  final int markupMinor;
  final String? passengerUserId;
  final bool assignmentLocked;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'seat_code': seatCode.dbValue,
      'seat_type': seatType.dbValue,
      'base_fare_minor': baseFareMinor,
      'markup_minor': markupMinor,
      'passenger_user_id': passengerUserId,
      'assignment_locked': assignmentLocked ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Seat.fromMap(Map<String, Object?> map) {
    return Seat(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      seatCode: SeatCode.fromDbValue(map['seat_code'] as String),
      seatType: SeatType.fromDbValue(map['seat_type'] as String),
      baseFareMinor: (map['base_fare_minor'] as num?)?.toInt() ?? 0,
      markupMinor: (map['markup_minor'] as num?)?.toInt() ?? 0,
      passengerUserId: map['passenger_user_id'] as String?,
      assignmentLocked: ((map['assignment_locked'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
