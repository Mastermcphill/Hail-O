import 'package:sqflite_common/sqlite_api.dart';

import 'phone_auth_store.dart';

class SqlitePhoneAuthStore extends PhoneAuthStore {
  SqlitePhoneAuthStore(this.db);

  final DatabaseExecutor db;

  @override
  Future<OtpChallengeRecord?> findLatestOtpChallenge(String phoneE164) async {
    final rows = await db.query(
      'otp_challenges',
      where: 'phone_e164 = ?',
      whereArgs: <Object>[phoneE164],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _otpChallengeFromRow(rows.first);
  }

  @override
  Future<void> createOtpChallenge(OtpChallengeRecord challenge) {
    return db.insert('otp_challenges', <String, Object?>{
      'id': challenge.id,
      'phone_e164': challenge.phoneE164,
      'code_hash': challenge.codeHash,
      'expires_at': challenge.expiresAt.toUtc().toIso8601String(),
      'attempts': challenge.attempts,
      'locked_until': challenge.lockedUntil?.toUtc().toIso8601String(),
      'created_at': challenge.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> updateOtpChallengeState({
    required String challengeId,
    required int attempts,
    required DateTime? lockedUntil,
  }) {
    return db.update(
      'otp_challenges',
      <String, Object?>{
        'attempts': attempts,
        'locked_until': lockedUntil?.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object>[challengeId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> consumeOtpChallenge({
    required String challengeId,
    required DateTime consumedAt,
  }) {
    final nowIso = consumedAt.toUtc().toIso8601String();
    return db.update(
      'otp_challenges',
      <String, Object?>{'expires_at': nowIso, 'locked_until': nowIso},
      where: 'id = ?',
      whereArgs: <Object>[challengeId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<PhoneAuthUserRecord?> findUserByPhone(String phoneE164) async {
    final rows = await db.query(
      'users',
      columns: <String>['id', 'phone_e164', 'created_at', 'role'],
      where: 'phone_e164 = ?',
      whereArgs: <Object>[phoneE164],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _userFromRow(rows.first);
  }

  @override
  Future<PhoneAuthUserRecord?> findUserById(String userId) async {
    final rows = await db.query(
      'users',
      columns: <String>['id', 'phone_e164', 'created_at', 'role'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _userFromRow(rows.first);
  }

  @override
  Future<bool> isUserDisabled(String userId) async {
    try {
      final rows = await db.query(
        'users',
        columns: <String>['disabled_at'],
        where: 'id = ?',
        whereArgs: <Object>[userId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return false;
      }
      final disabledAt = (rows.first['disabled_at'] as String?)?.trim() ?? '';
      return disabledAt.isNotEmpty;
    } on DatabaseException {
      return false;
    }
  }

  @override
  Future<PhoneAuthUserRecord> createUser({
    required String userId,
    required String phoneE164,
    required DateTime createdAt,
  }) async {
    final nowIso = createdAt.toUtc().toIso8601String();
    late final PhoneAuthUserRecord user;
    try {
      await db.insert('users', <String, Object?>{
        'id': userId,
        'role': 'rider',
        'phone_e164': phoneE164,
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      user = PhoneAuthUserRecord(
        id: userId,
        phoneE164: phoneE164,
        createdAt: createdAt.toUtc(),
        role: 'rider',
      );
    } on DatabaseException {
      final existing = await findUserByPhone(phoneE164);
      if (existing != null) {
        user = existing;
      } else {
        rethrow;
      }
    }
    await _ensureProfile(user.id, nowIso);
    await _ensureRole(user.id, 'user');
    return user;
  }

  @override
  Future<void> createRefreshToken(RefreshTokenRecord token) {
    return db.insert('refresh_tokens', <String, Object?>{
      'id': token.id,
      'user_id': token.userId,
      'token_hash': token.tokenHash,
      'expires_at': token.expiresAt.toUtc().toIso8601String(),
      'revoked_at': token.revokedAt?.toUtc().toIso8601String(),
      'created_at': token.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<RefreshTokenRecord?> findRefreshTokenByHash(String tokenHash) async {
    final rows = await db.query(
      'refresh_tokens',
      where: 'token_hash = ?',
      whereArgs: <Object>[tokenHash],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _refreshTokenFromRow(rows.first);
  }

  @override
  Future<void> revokeRefreshToken({
    required String tokenId,
    required DateTime revokedAt,
  }) {
    return db.update(
      'refresh_tokens',
      <String, Object?>{'revoked_at': revokedAt.toUtc().toIso8601String()},
      where: 'id = ? AND revoked_at IS NULL',
      whereArgs: <Object>[tokenId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  OtpChallengeRecord _otpChallengeFromRow(Map<String, Object?> row) {
    return OtpChallengeRecord(
      id: (row['id'] as String?) ?? '',
      phoneE164: (row['phone_e164'] as String?) ?? '',
      codeHash: (row['code_hash'] as String?) ?? '',
      expiresAt: DateTime.parse((row['expires_at'] as String?) ?? '').toUtc(),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      lockedUntil: _parseOptionalUtc(row['locked_until']),
      createdAt: DateTime.parse((row['created_at'] as String?) ?? '').toUtc(),
    );
  }

  PhoneAuthUserRecord _userFromRow(Map<String, Object?> row) {
    return PhoneAuthUserRecord(
      id: (row['id'] as String?) ?? '',
      phoneE164: (row['phone_e164'] as String?) ?? '',
      createdAt: DateTime.parse((row['created_at'] as String?) ?? '').toUtc(),
      role: (row['role'] as String?)?.trim().toLowerCase() == 'driver'
          ? 'driver'
          : (row['role'] as String?)?.trim().toLowerCase() == 'admin'
          ? 'admin'
          : (row['role'] as String?)?.trim().toLowerCase() == 'fleet_owner'
          ? 'fleet_owner'
          : 'rider',
    );
  }

  RefreshTokenRecord _refreshTokenFromRow(Map<String, Object?> row) {
    return RefreshTokenRecord(
      id: (row['id'] as String?) ?? '',
      userId: (row['user_id'] as String?) ?? '',
      tokenHash: (row['token_hash'] as String?) ?? '',
      expiresAt: DateTime.parse((row['expires_at'] as String?) ?? '').toUtc(),
      revokedAt: _parseOptionalUtc(row['revoked_at']),
      createdAt: DateTime.parse((row['created_at'] as String?) ?? '').toUtc(),
    );
  }

  DateTime? _parseOptionalUtc(Object? value) {
    final raw = (value as String?)?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.parse(raw).toUtc();
  }

  Future<void> _ensureProfile(String userId, String nowIso) {
    return db.insert('user_profiles', <String, Object?>{
      'user_id': userId,
      'display_name': null,
      'email': null,
      'avatar_url': null,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _ensureRole(String userId, String role) {
    return db.insert('user_roles', <String, Object?>{
      'user_id': userId,
      'role': role,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
