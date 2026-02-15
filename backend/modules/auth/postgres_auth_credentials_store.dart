import 'package:hail_o_finance_core/domain/services/auth_service.dart';

import '../../infra/postgres_provider.dart';
import 'auth_credentials_store.dart';

class PostgresAuthCredentialsStore extends AuthCredentialsStore {
  PostgresAuthCredentialsStore(this._postgresProvider);

  final PostgresProvider _postgresProvider;

  @override
  Future<ExternalAuthCredentialRecord?> findByEmail(String email) async {
    final connection = await _postgresProvider.open();
    final result = await connection.query(
      '''
      SELECT user_id, email, password_hash, password_algo, role, created_at, updated_at
      FROM auth_credentials
      WHERE email = @email
      LIMIT 1
      ''',
      substitutionValues: <String, Object?>{
        'email': email.toLowerCase().trim(),
      },
    );
    if (result.isEmpty) {
      return null;
    }
    final row = result.first;
    return ExternalAuthCredentialRecord(
      userId: row[0] as String,
      email: row[1] as String,
      passwordHash: row[2] as String,
      passwordAlgo: (row[3] as String?) ?? 'bcrypt',
      role: row[4] as String,
      createdAt: (row[5] as DateTime).toUtc(),
      updatedAt: (row[6] as DateTime).toUtc(),
    );
  }

  @override
  Future<void> upsertCredential(ExternalAuthCredentialRecord record) async {
    final connection = await _postgresProvider.open();
    await connection.query(
      '''
      INSERT INTO auth_credentials(
        user_id,
        email,
        password_hash,
        password_algo,
        role,
        created_at,
        updated_at
      )
      VALUES(
        @user_id,
        @email,
        @password_hash,
        @password_algo,
        @role,
        @created_at,
        @updated_at
      )
      ON CONFLICT (email)
      DO UPDATE
      SET
        user_id = EXCLUDED.user_id,
        password_hash = EXCLUDED.password_hash,
        password_algo = EXCLUDED.password_algo,
        role = EXCLUDED.role,
        updated_at = EXCLUDED.updated_at
      ''',
      substitutionValues: <String, Object?>{
        'user_id': record.userId,
        'email': record.email.toLowerCase().trim(),
        'password_hash': record.passwordHash,
        'password_algo': record.passwordAlgo,
        'role': record.role,
        'created_at': record.createdAt.toUtc(),
        'updated_at': record.updatedAt.toUtc(),
      },
    );
  }
}
