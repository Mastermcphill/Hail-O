class PhoneAuthUserRecord {
  const PhoneAuthUserRecord({
    required this.id,
    required this.phoneE164,
    required this.createdAt,
    required this.role,
  });

  final String id;
  final String phoneE164;
  final DateTime createdAt;
  final String role;
}

class OtpChallengeRecord {
  const OtpChallengeRecord({
    required this.id,
    required this.phoneE164,
    required this.codeHash,
    required this.expiresAt,
    required this.attempts,
    required this.lockedUntil,
    required this.createdAt,
  });

  final String id;
  final String phoneE164;
  final String codeHash;
  final DateTime expiresAt;
  final int attempts;
  final DateTime? lockedUntil;
  final DateTime createdAt;
}

class RefreshTokenRecord {
  const RefreshTokenRecord({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String tokenHash;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;
}

abstract class PhoneAuthStore {
  Future<OtpChallengeRecord?> findLatestOtpChallenge(String phoneE164);

  Future<void> createOtpChallenge(OtpChallengeRecord challenge);

  Future<void> updateOtpChallengeState({
    required String challengeId,
    required int attempts,
    required DateTime? lockedUntil,
  });

  Future<void> consumeOtpChallenge({
    required String challengeId,
    required DateTime consumedAt,
  });

  Future<PhoneAuthUserRecord?> findUserByPhone(String phoneE164);

  Future<PhoneAuthUserRecord?> findUserById(String userId);

  Future<bool> isUserDisabled(String userId);

  Future<PhoneAuthUserRecord> createUser({
    required String userId,
    required String phoneE164,
    required DateTime createdAt,
  });

  Future<void> createRefreshToken(RefreshTokenRecord token);

  Future<RefreshTokenRecord?> findRefreshTokenByHash(String tokenHash);

  Future<void> revokeRefreshToken({
    required String tokenId,
    required DateTime revokedAt,
  });
}
