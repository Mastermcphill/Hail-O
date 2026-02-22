class AuthCredential {
  const AuthCredential({
    required this.userId,
    required this.email,
    required this.passwordHash,
    this.passwordAlgo = 'bcrypt',
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String email;
  final String passwordHash;
  final String passwordAlgo;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'user_id': userId,
      'email': email,
      'password_hash': passwordHash,
      'password_algo': passwordAlgo,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory AuthCredential.fromMap(Map<String, Object?> map) {
    return AuthCredential(
      userId: map['user_id'] as String,
      email: map['email'] as String,
      passwordHash: map['password_hash'] as String,
      passwordAlgo: (map['password_algo'] as String?) ?? 'bcrypt',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
