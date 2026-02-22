class NextOfKin {
  const NextOfKin({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.createdAt,
    required this.updatedAt,
    this.relationship,
  });

  final String userId;
  final String fullName;
  final String phone;
  final String? relationship;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'user_id': userId,
      'full_name': fullName,
      'phone': phone,
      'relationship': relationship,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory NextOfKin.fromMap(Map<String, Object?> map) {
    return NextOfKin(
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String,
      relationship: map['relationship'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
