class ReferralCode {
  const ReferralCode({
    required this.code,
    required this.referrerUserId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String code;
  final String referrerUserId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'code': code,
      'referrer_user_id': referrerUserId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ReferralCode.fromMap(Map<String, Object?> map) {
    return ReferralCode(
      code: map['code'] as String,
      referrerUserId: map['referrer_user_id'] as String,
      isActive: ((map['is_active'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
