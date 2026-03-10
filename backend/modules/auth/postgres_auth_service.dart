import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/postgres_provider.dart';

class PostgresAuthService implements AuthAccountService {
  PostgresAuthService(
    this._postgresProvider, {
    DateTime Function()? nowUtc,
    Uuid? uuid,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid();

  final PostgresProvider _postgresProvider;
  final DateTime Function() _nowUtc;
  final Uuid _uuid;

  @override
  Future<Map<String, Object?>> register({
    required String email,
    required String password,
    required UserRole role,
    required String idempotencyKey,
    String? displayName,
    RegisterNextOfKinInput? nextOfKin,
    String? referralCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const DomainInvariantError(code: 'invalid_email');
    }
    if (password.length < 8) {
      throw const DomainInvariantError(code: 'weak_password');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw const DomainInvariantError(code: 'idempotency_key_required');
    }

    final now = _nowUtc();
    final userId = _uuid.v4();
    final hashed = BCrypt.hashpw(password, BCrypt.gensalt());
    final syntheticPhone = _syntheticPhoneE164(userId);

    try {
      await _postgresProvider.withConnection((connection) async {
        await connection.transaction((ctx) async {
          await ctx.execute(
            '''
            INSERT INTO users(id, phone_e164, created_at)
            VALUES(CAST(@id AS UUID), @phone_e164, @created_at)
            ''',
            substitutionValues: <String, Object?>{
              'id': userId,
              'phone_e164': syntheticPhone,
              'created_at': now.toUtc(),
            },
          );

          await ctx.execute(
            '''
            INSERT INTO user_profiles(user_id, display_name, email, avatar_url, updated_at)
            VALUES(CAST(@user_id AS UUID), @display_name, @email, NULL, @updated_at)
            ON CONFLICT (user_id)
            DO UPDATE
            SET
              display_name = EXCLUDED.display_name,
              email = EXCLUDED.email,
              updated_at = EXCLUDED.updated_at
            ''',
            substitutionValues: <String, Object?>{
              'user_id': userId,
              'display_name': _normalizeNullable(displayName),
              'email': normalizedEmail,
              'updated_at': now.toUtc(),
            },
          );

          for (final scaffoldRole in _scaffoldRoles(role)) {
            await ctx.execute(
              '''
              INSERT INTO user_roles(user_id, role)
              VALUES(CAST(@user_id AS UUID), @role)
              ON CONFLICT (user_id, role) DO NOTHING
              ''',
              substitutionValues: <String, Object?>{
                'user_id': userId,
                'role': scaffoldRole,
              },
            );
          }

          final inserted = await ctx.query(
            '''
            INSERT INTO auth_credentials(
              user_id,
              email,
              phone,
              password_hash,
              password_algo,
              role,
              created_at,
              updated_at
            )
            VALUES(
              @user_id,
              @email,
              @phone,
              @password_hash,
              @password_algo,
              @role,
              @created_at,
              @updated_at
            )
            ON CONFLICT (email) DO NOTHING
            RETURNING user_id
            ''',
            substitutionValues: <String, Object?>{
              'user_id': userId,
              'email': normalizedEmail,
              'phone': syntheticPhone,
              'password_hash': hashed,
              'password_algo': 'bcrypt',
              'role': role.dbValue,
              'created_at': now.toUtc(),
              'updated_at': now.toUtc(),
            },
          );
          if (inserted.isEmpty) {
            throw const DomainInvariantError(code: 'email_already_registered');
          }
        });
      });
    } catch (error) {
      if (error is DomainError) {
        rethrow;
      }
      final existing = await _findByEmail(normalizedEmail);
      if (existing != null) {
        throw const DomainInvariantError(code: 'email_already_registered');
      }
      rethrow;
    }

    return <String, Object?>{
      'ok': true,
      'replayed': false,
      'user_id': userId,
      'email': normalizedEmail,
      'role': role.dbValue,
      'result_hash': sha256
          .convert(utf8.encode('$userId|$normalizedEmail'))
          .toString(),
    };
  }

  @override
  Future<Map<String, Object?>> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const UnauthorizedActionError(code: 'invalid_credentials');
    }

    final credential = await _findByEmail(normalizedEmail);
    if (credential == null ||
        !BCrypt.checkpw(password, credential.passwordHash)) {
      throw const UnauthorizedActionError(code: 'invalid_credentials');
    }
    if (await _isUserDisabled(credential.userId)) {
      throw const UnauthorizedActionError(code: 'user_disabled');
    }

    return <String, Object?>{
      'ok': true,
      'user_id': credential.userId,
      'role': credential.role,
      'email': credential.email,
    };
  }

  Future<ExternalAuthCredentialRecord?> _findByEmail(String email) async {
    final result = await _postgresProvider.withConnection(
      (connection) => connection.query(
        '''
        SELECT user_id, email, password_hash, password_algo, role, created_at, updated_at
        FROM auth_credentials
        WHERE email = @email
        LIMIT 1
        ''',
        substitutionValues: <String, Object?>{
          'email': email.toLowerCase().trim(),
        },
      ),
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

  Future<bool> _isUserDisabled(String userId) async {
    try {
      final rows = await _postgresProvider.withConnection(
        (connection) => connection.query(
          '''
          SELECT disabled_at
          FROM users
          WHERE id = CAST(@id AS UUID)
          LIMIT 1
          ''',
          substitutionValues: <String, Object?>{'id': userId},
        ),
      );
      if (rows.isEmpty) {
        return false;
      }
      return rows.first[0] != null;
    } catch (_) {
      return false;
    }
  }

  Iterable<String> _scaffoldRoles(UserRole role) sync* {
    yield 'user';
    switch (role) {
      case UserRole.admin:
        yield 'admin';
        break;
      case UserRole.driver:
        yield 'driver';
        break;
      case UserRole.fleetOwner:
        yield 'merchant';
        break;
      case UserRole.rider:
        break;
    }
  }

  String? _normalizeNullable(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _syntheticPhoneE164(String userId) {
    final digest = sha256.convert(utf8.encode(userId)).bytes;
    final digits = StringBuffer();
    for (final byte in digest) {
      digits.write(byte % 10);
      if (digits.length >= 12) {
        break;
      }
    }
    while (digits.length < 12) {
      digits.write('0');
    }
    return '+999${digits.toString()}';
  }
}
