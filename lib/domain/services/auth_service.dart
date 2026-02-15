import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/auth_credentials_dao.dart';
import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/next_of_kin_dao.dart';
import '../../data/sqlite/dao/users_dao.dart';
import '../errors/domain_errors.dart';
import '../models/auth_credential.dart';
import '../models/idempotency_record.dart';
import '../models/next_of_kin.dart';
import '../models/user.dart';

class RegisterNextOfKinInput {
  const RegisterNextOfKinInput({
    required this.fullName,
    required this.phone,
    this.relationship,
  });

  final String fullName;
  final String phone;
  final String? relationship;
}

class ExternalAuthCredentialRecord {
  const ExternalAuthCredentialRecord({
    required this.userId,
    required this.email,
    required this.passwordHash,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.passwordAlgo = 'bcrypt',
  });

  final String userId;
  final String email;
  final String passwordHash;
  final String passwordAlgo;
  final String role;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract class AuthCredentialsExternalStore {
  Future<void> upsertCredential(ExternalAuthCredentialRecord record);

  Future<ExternalAuthCredentialRecord?> findByEmail(String email);
}

class AuthService {
  AuthService(
    this.db, {
    DateTime Function()? nowUtc,
    Uuid? uuid,
    AuthCredentialsExternalStore? externalStore,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid(),
       _idempotencyStore = IdempotencyDao(db),
       _externalStore = externalStore;

  final Database db;
  final DateTime Function() _nowUtc;
  final Uuid _uuid;
  final IdempotencyStore _idempotencyStore;
  final AuthCredentialsExternalStore? _externalStore;

  static const String _scopeRegister = 'api.auth.register';

  Future<Map<String, Object?>> register({
    required String email,
    required String password,
    required UserRole role,
    required String idempotencyKey,
    String? displayName,
    RegisterNextOfKinInput? nextOfKin,
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

    final claim = await _idempotencyStore.claim(
      scope: _scopeRegister,
      key: idempotencyKey,
      requestHash: '$normalizedEmail|${role.dbValue}',
    );
    if (!claim.isNewClaim) {
      if (claim.record.status == IdempotencyStatus.success) {
        final existing = await AuthCredentialsDao(
          db,
        ).findByEmail(normalizedEmail);
        if (existing != null) {
          return <String, Object?>{
            'ok': true,
            'replayed': true,
            'user_id': existing.userId,
            'email': existing.email,
            'result_hash': claim.record.resultHash,
          };
        }
        final external = await _externalStore?.findByEmail(normalizedEmail);
        if (external != null) {
          return <String, Object?>{
            'ok': true,
            'replayed': true,
            'user_id': external.userId,
            'email': external.email,
            'result_hash': claim.record.resultHash,
          };
        }
        throw const DomainInvariantError(code: 'register_replay_missing_user');
      }
      throw DomainInvariantError(
        code: claim.record.errorCode ?? 'register_previous_failure',
      );
    }

    try {
      final now = _nowUtc();
      final userId = _uuid.v4();
      final hashed = BCrypt.hashpw(password, BCrypt.gensalt());

      final result = await db.transaction((txn) async {
        final credentialsDao = AuthCredentialsDao(txn);
        final existing = await credentialsDao.findByEmail(normalizedEmail);
        if (existing != null) {
          throw const DomainInvariantError(code: 'email_already_registered');
        }

        final user = User(
          id: userId,
          role: role,
          email: normalizedEmail,
          displayName: displayName,
          createdAt: now,
          updatedAt: now,
        );
        await UsersDao(txn).insert(user);
        await credentialsDao.insert(
          AuthCredential(
            userId: userId,
            email: normalizedEmail,
            passwordHash: hashed,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (nextOfKin != null) {
          await NextOfKinDao(txn).upsert(
            NextOfKin(
              userId: userId,
              fullName: nextOfKin.fullName.trim(),
              phone: nextOfKin.phone.trim(),
              relationship: nextOfKin.relationship?.trim(),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        return <String, Object?>{
          'ok': true,
          'replayed': false,
          'user_id': userId,
          'email': normalizedEmail,
          'role': role.dbValue,
        };
      });

      final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
      if (_externalStore != null) {
        await _externalStore.upsertCredential(
          ExternalAuthCredentialRecord(
            userId: userId,
            email: normalizedEmail,
            passwordHash: hashed,
            role: role.dbValue,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeRegister,
        key: idempotencyKey,
        resultHash: hash,
      );
      return <String, Object?>{...result, 'result_hash': hash};
    } catch (error) {
      final code = error is DomainError ? error.code : 'register_exception';
      await _idempotencyStore.finalizeFailure(
        scope: _scopeRegister,
        key: idempotencyKey,
        errorCode: code,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const UnauthorizedActionError(code: 'invalid_credentials');
    }

    if (_externalStore != null) {
      final external = await _externalStore.findByEmail(normalizedEmail);
      if (external != null && BCrypt.checkpw(password, external.passwordHash)) {
        final user = await UsersDao(db).findById(external.userId);
        if (user != null && user.isBlocked) {
          throw const UnauthorizedActionError(code: 'user_blocked');
        }
        return <String, Object?>{
          'ok': true,
          'user_id': external.userId,
          'role': external.role,
          'email': external.email,
        };
      }
    }

    final credential = await AuthCredentialsDao(
      db,
    ).findByEmail(normalizedEmail);
    if (credential == null ||
        !BCrypt.checkpw(password, credential.passwordHash)) {
      throw const UnauthorizedActionError(code: 'invalid_credentials');
    }
    final user = await UsersDao(db).findById(credential.userId);
    if (user == null) {
      throw const DomainInvariantError(code: 'user_not_found');
    }
    if (user.isBlocked) {
      throw const UnauthorizedActionError(code: 'user_blocked');
    }

    return <String, Object?>{
      'ok': true,
      'user_id': user.id,
      'role': user.role.dbValue,
      'email': user.email,
    };
  }
}
