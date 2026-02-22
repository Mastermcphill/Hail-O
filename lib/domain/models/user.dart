enum UserRole {
  rider('rider'),
  driver('driver'),
  fleetOwner('fleet_owner'),
  admin('admin');

  const UserRole(this.dbValue);

  final String dbValue;

  static UserRole fromDbValue(String value) {
    return UserRole.values.firstWhere(
      (role) => role.dbValue == value,
      orElse: () => UserRole.rider,
    );
  }
}

class User {
  const User({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.displayName,
    this.gender,
    this.tribe,
    this.starRating = 0,
    this.luggageCount = 0,
    this.nextOfKinLocked = true,
    this.crossBorderDocLocked = true,
    this.allowLocationOff = false,
    this.isBlocked = false,
    this.disclosureAccepted = false,
  });

  final String id;
  final UserRole role;
  final String? email;
  final String? displayName;
  final String? gender;
  final String? tribe;
  final double starRating;
  final int luggageCount;
  final bool nextOfKinLocked;
  final bool crossBorderDocLocked;
  final bool allowLocationOff;
  final bool isBlocked;
  final bool disclosureAccepted;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'role': role.dbValue,
      'email': email,
      'display_name': displayName,
      'gender': gender,
      'tribe': tribe,
      'star_rating': starRating,
      'luggage_count': luggageCount,
      'next_of_kin_locked': nextOfKinLocked ? 1 : 0,
      'cross_border_doc_locked': crossBorderDocLocked ? 1 : 0,
      'allow_location_off': allowLocationOff ? 1 : 0,
      'is_blocked': isBlocked ? 1 : 0,
      'disclosure_accepted': disclosureAccepted ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, Object?> map) {
    return User(
      id: map['id'] as String,
      role: UserRole.fromDbValue(map['role'] as String),
      email: map['email'] as String?,
      displayName: map['display_name'] as String?,
      gender: map['gender'] as String?,
      tribe: map['tribe'] as String?,
      starRating: (map['star_rating'] as num?)?.toDouble() ?? 0,
      luggageCount: (map['luggage_count'] as num?)?.toInt() ?? 0,
      nextOfKinLocked: ((map['next_of_kin_locked'] as num?)?.toInt() ?? 0) == 1,
      crossBorderDocLocked:
          ((map['cross_border_doc_locked'] as num?)?.toInt() ?? 0) == 1,
      allowLocationOff:
          ((map['allow_location_off'] as num?)?.toInt() ?? 0) == 1,
      isBlocked: ((map['is_blocked'] as num?)?.toInt() ?? 0) == 1,
      disclosureAccepted:
          ((map['disclosure_accepted'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
