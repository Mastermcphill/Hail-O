import '../../infra/postgres_provider.dart';
import 'phone_auth_store.dart';

class PostgresPhoneAuthStore extends PhoneAuthStore {
  PostgresPhoneAuthStore(this._postgresProvider);

  final PostgresProvider _postgresProvider;

  @override
  Future<OtpChallengeRecord?> findLatestOtpChallenge(String phoneE164) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id::text, phone_e164, code_hash, expires_at, attempts, locked_until, created_at
        FROM otp_challenges
        WHERE phone_e164 = @phone_e164
        ORDER BY created_at DESC
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'phone_e164': phoneE164},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return OtpChallengeRecord(
      id: row[0] as String,
      phoneE164: row[1] as String,
      codeHash: row[2] as String,
      expiresAt: (row[3] as DateTime).toUtc(),
      attempts: (row[4] as num?)?.toInt() ?? 0,
      lockedUntil: (row[5] as DateTime?)?.toUtc(),
      createdAt: (row[6] as DateTime).toUtc(),
    );
  }

  @override
  Future<void> createOtpChallenge(OtpChallengeRecord challenge) {
    return _postgresProvider.withConnection((connection) {
      return connection.execute(
        '''
        INSERT INTO otp_challenges(
          id,
          phone_e164,
          code_hash,
          expires_at,
          attempts,
          locked_until,
          created_at
        )
        VALUES(
          CAST(@id AS UUID),
          @phone_e164,
          @code_hash,
          @expires_at,
          @attempts,
          @locked_until,
          @created_at
        )
        ''',
        substitutionValues: <String, Object?>{
          'id': challenge.id,
          'phone_e164': challenge.phoneE164,
          'code_hash': challenge.codeHash,
          'expires_at': challenge.expiresAt.toUtc(),
          'attempts': challenge.attempts,
          'locked_until': challenge.lockedUntil?.toUtc(),
          'created_at': challenge.createdAt.toUtc(),
        },
      );
    });
  }

  @override
  Future<void> updateOtpChallengeState({
    required String challengeId,
    required int attempts,
    required DateTime? lockedUntil,
  }) {
    return _postgresProvider.withConnection((connection) {
      return connection.execute(
        '''
        UPDATE otp_challenges
        SET attempts = @attempts, locked_until = @locked_until
        WHERE id = CAST(@id AS UUID)
        ''',
        substitutionValues: <String, Object?>{
          'id': challengeId,
          'attempts': attempts,
          'locked_until': lockedUntil?.toUtc(),
        },
      );
    });
  }

  @override
  Future<void> consumeOtpChallenge({
    required String challengeId,
    required DateTime consumedAt,
  }) {
    return _postgresProvider.withConnection((connection) {
      return connection.execute(
        '''
        UPDATE otp_challenges
        SET expires_at = @consumed_at, locked_until = @consumed_at
        WHERE id = CAST(@id AS UUID)
        ''',
        substitutionValues: <String, Object?>{
          'id': challengeId,
          'consumed_at': consumedAt.toUtc(),
        },
      );
    });
  }

  @override
  Future<PhoneAuthUserRecord?> findUserByPhone(String phoneE164) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id::text, phone_e164, created_at
        FROM users
        WHERE phone_e164 = @phone_e164
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'phone_e164': phoneE164},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return PhoneAuthUserRecord(
      id: row[0] as String,
      phoneE164: row[1] as String,
      createdAt: (row[2] as DateTime).toUtc(),
      role: 'rider',
    );
  }

  @override
  Future<PhoneAuthUserRecord?> findUserById(String userId) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id::text, phone_e164, created_at
        FROM users
        WHERE id = CAST(@id AS UUID)
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'id': userId},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return PhoneAuthUserRecord(
      id: row[0] as String,
      phoneE164: row[1] as String,
      createdAt: (row[2] as DateTime).toUtc(),
      role: 'rider',
    );
  }

  @override
  Future<PhoneAuthUserRecord> createUser({
    required String userId,
    required String phoneE164,
    required DateTime createdAt,
  }) async {
    final inserted = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        INSERT INTO users(id, phone_e164, created_at)
        VALUES(CAST(@id AS UUID), @phone_e164, @created_at)
        ON CONFLICT (phone_e164)
        DO NOTHING
        RETURNING id::text, phone_e164, created_at
        ''',
        substitutionValues: <String, Object?>{
          'id': userId,
          'phone_e164': phoneE164,
          'created_at': createdAt.toUtc(),
        },
      ),
    );
    late final PhoneAuthUserRecord user;
    if (inserted.isNotEmpty) {
      final row = inserted.first;
      user = PhoneAuthUserRecord(
        id: row[0] as String,
        phoneE164: row[1] as String,
        createdAt: (row[2] as DateTime).toUtc(),
        role: 'rider',
      );
    } else {
      final existing = await findUserByPhone(phoneE164);
      if (existing == null) {
        throw StateError('phone_auth_user_create_failed');
      }
      user = existing;
    }
    await _ensureDefaultUserScaffold(userId: user.id, createdAt: createdAt);
    return user;
  }

  @override
  Future<void> createRefreshToken(RefreshTokenRecord token) {
    return _postgresProvider.withConnection((connection) {
      return connection.execute(
        '''
        INSERT INTO refresh_tokens(
          id,
          user_id,
          token_hash,
          expires_at,
          revoked_at,
          created_at
        )
        VALUES(
          CAST(@id AS UUID),
          CAST(@user_id AS UUID),
          @token_hash,
          @expires_at,
          @revoked_at,
          @created_at
        )
        ''',
        substitutionValues: <String, Object?>{
          'id': token.id,
          'user_id': token.userId,
          'token_hash': token.tokenHash,
          'expires_at': token.expiresAt.toUtc(),
          'revoked_at': token.revokedAt?.toUtc(),
          'created_at': token.createdAt.toUtc(),
        },
      );
    });
  }

  @override
  Future<RefreshTokenRecord?> findRefreshTokenByHash(String tokenHash) async {
    final rows = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT id::text, user_id::text, token_hash, expires_at, revoked_at, created_at
        FROM refresh_tokens
        WHERE token_hash = @token_hash
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{'token_hash': tokenHash},
      ),
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return RefreshTokenRecord(
      id: row[0] as String,
      userId: row[1] as String,
      tokenHash: row[2] as String,
      expiresAt: (row[3] as DateTime).toUtc(),
      revokedAt: (row[4] as DateTime?)?.toUtc(),
      createdAt: (row[5] as DateTime).toUtc(),
    );
  }

  @override
  Future<void> revokeRefreshToken({
    required String tokenId,
    required DateTime revokedAt,
  }) {
    return _postgresProvider.withConnection((connection) {
      return connection.execute(
        '''
        UPDATE refresh_tokens
        SET revoked_at = @revoked_at
        WHERE id = CAST(@id AS UUID)
          AND revoked_at IS NULL
        ''',
        substitutionValues: <String, Object?>{
          'id': tokenId,
          'revoked_at': revokedAt.toUtc(),
        },
      );
    });
  }

  Future<void> _ensureDefaultUserScaffold({
    required String userId,
    required DateTime createdAt,
  }) async {
    await _postgresProvider.withConnection((connection) async {
      await connection.execute(
        '''
        INSERT INTO user_profiles(user_id, display_name, email, avatar_url, updated_at)
        VALUES(CAST(@user_id AS UUID), NULL, NULL, NULL, @updated_at)
        ON CONFLICT (user_id)
        DO NOTHING
        ''',
        substitutionValues: <String, Object?>{
          'user_id': userId,
          'updated_at': createdAt.toUtc(),
        },
      );
      await connection.execute(
        '''
        INSERT INTO user_roles(user_id, role)
        VALUES(CAST(@user_id AS UUID), @role)
        ON CONFLICT (user_id, role)
        DO NOTHING
        ''',
        substitutionValues: <String, Object?>{
          'user_id': userId,
          'role': 'user',
        },
      );
    });
  }
}
