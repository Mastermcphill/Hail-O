import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'finance_database.dart';

class MoneyBoxService {
  MoneyBoxService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final DateTime Function() _nowUtc;

  Future<Map<String, Object?>> ensureAccount({
    required String ownerId,
    int tier = 1,
    String status = 'active',
    int autosavePercent = 0,
    DateTime? lockStart,
    DateTime? autoOpenDate,
    DateTime? maturityDate,
  }) async {
    final now = _nowUtc();
    final safeTier = tier.clamp(1, 4);
    final safeAutosave = autosavePercent.clamp(0, 30);
    final lock = lockStart ?? now;
    final openDate =
        autoOpenDate ??
        lock.add(_tierDuration(safeTier) - const Duration(days: 1));
    final maturity = maturityDate ?? lock.add(_tierDuration(safeTier));
    final nowIso = isoNowUtc(now);

    await db.insert('moneybox_accounts', <String, Object?>{
      'owner_id': ownerId,
      'tier': safeTier,
      'lock_start': isoNowUtc(lock),
      'auto_open_date': isoNowUtc(openDate),
      'maturity_date': isoNowUtc(maturity),
      'principal_minor': 0,
      'projected_bonus_minor': 0,
      'expected_at_maturity_minor': 0,
      'autosave_percent': safeAutosave,
      'bonus_eligible': 1,
      'status': status,
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return getAccount(ownerId);
  }

  Future<Map<String, Object?>> getAccount(String ownerId) async {
    final rows = await db.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ensureAccount(ownerId: ownerId);
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>> setAutosave({
    required String ownerId,
    required int percent,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final safe = percent.clamp(0, 30);
    const scope = 'moneybox_set_autosave';
    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readHash(txn, scope: scope, key: idempotencyKey);
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      await _ensureAccountTx(txn, ownerId);
      final nowIso = isoNowUtc(_nowUtc());
      await txn.update(
        'moneybox_accounts',
        <String, Object?>{'autosave_percent': safe, 'updated_at': nowIso},
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      final account = await _accountTx(txn, ownerId);
      final result = <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'autosave_percent': safe,
        'status': account['status'],
      };
      await _finalize(txn, scope: scope, key: idempotencyKey, result: result);
      return result;
    });
  }

  Future<Map<String, Object?>> creditPrincipalFromAutosave({
    required String ownerId,
    required int amountMinor,
    required String sourceKind,
    required String referenceId,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    if (amountMinor <= 0) {
      throw ArgumentError('amountMinor must be > 0');
    }
    const scope = 'moneybox_credit_principal';

    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readHash(txn, scope: scope, key: idempotencyKey);
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      await _ensureAccountTx(txn, ownerId);
      final account = await _accountTx(txn, ownerId);

      final tier = (account['tier'] as int?) ?? 1;
      final principalBefore = (account['principal_minor'] as int?) ?? 0;
      final principalAfter = principalBefore + amountMinor;
      final projectedBonusAfter = _projectedBonus(principalAfter, tier);
      final expectedAfter = principalAfter + projectedBonusAfter;
      final nowIso = isoNowUtc(_nowUtc());

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'principal_minor': principalAfter,
          'projected_bonus_minor': projectedBonusAfter,
          'expected_at_maturity_minor': expectedAfter,
          'updated_at': nowIso,
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      await txn.insert('moneybox_ledger', <String, Object?>{
        'owner_id': ownerId,
        'entry_type': 'autosave_credit',
        'amount_minor': amountMinor,
        'principal_after_minor': principalAfter,
        'projected_bonus_after_minor': projectedBonusAfter,
        'expected_after_minor': expectedAfter,
        'source_kind': sourceKind,
        'reference_id': referenceId,
        'idempotency_scope': scope,
        'idempotency_key': '$idempotencyKey:moneybox_ledger',
        'created_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final result = <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'principal_after': principalAfter,
        'projected_bonus_after': projectedBonusAfter,
        'expected_after': expectedAfter,
        'saved_minor': amountMinor,
      };
      await _finalize(txn, scope: scope, key: idempotencyKey, result: result);
      return result;
    });
  }

  int projectedBonusFor({required int principalMinor, required int tier}) {
    return _projectedBonus(principalMinor, tier);
  }

  Duration _tierDuration(int tier) {
    if (tier == 2) return const Duration(days: 120);
    if (tier == 3) return const Duration(days: 210);
    if (tier == 4) return const Duration(days: 330);
    return const Duration(days: 30);
  }

  int _projectedBonus(int principalMinor, int tier) {
    final safePrincipal = principalMinor < 0 ? 0 : principalMinor;
    final pct = switch (tier) {
      2 => 3,
      3 => 8,
      4 => 15,
      _ => 0,
    };
    return percentOf(safePrincipal, pct);
  }

  Future<void> _ensureAccountTx(Transaction txn, String ownerId) async {
    final now = _nowUtc();
    final nowIso = isoNowUtc(now);
    final lockStart = nowIso;
    final autoOpen = isoNowUtc(now.add(const Duration(days: 29)));
    final maturity = isoNowUtc(now.add(const Duration(days: 30)));

    await txn.insert('moneybox_accounts', <String, Object?>{
      'owner_id': ownerId,
      'tier': 1,
      'lock_start': lockStart,
      'auto_open_date': autoOpen,
      'maturity_date': maturity,
      'principal_minor': 0,
      'projected_bonus_minor': 0,
      'expected_at_maturity_minor': 0,
      'autosave_percent': 0,
      'bonus_eligible': 1,
      'status': 'active',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<Map<String, Object?>> _accountTx(
    Transaction txn,
    String ownerId,
  ) async {
    final rows = await txn.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('moneybox_account_not_found:$ownerId');
    }
    return Map<String, Object?>.from(rows.first);
  }

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
  }

  Future<bool> _claimIdempotency(
    Transaction txn, {
    required String scope,
    required String key,
  }) async {
    final now = isoNowUtc(_nowUtc());
    try {
      await txn.insert('idempotency_keys', <String, Object?>{
        'scope': scope,
        'key': key,
        'request_hash': null,
        'status': 'claimed',
        'result_hash': null,
        'error_code': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return false;
      }
      rethrow;
    }
  }

  Future<String> _readHash(
    Transaction txn, {
    required String scope,
    required String key,
  }) async {
    final rows = await txn.query(
      'idempotency_keys',
      columns: <String>['result_hash'],
      where: 'scope = ? AND "key" = ?',
      whereArgs: <Object>[scope, key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return '';
    }
    return (rows.first['result_hash'] as String?) ?? '';
  }

  Future<void> _finalize(
    Transaction txn, {
    required String scope,
    required String key,
    required Map<String, Object?> result,
  }) async {
    final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
    await txn.update(
      'idempotency_keys',
      <String, Object?>{
        'status': 'success',
        'result_hash': hash,
        'error_code': null,
        'updated_at': isoNowUtc(_nowUtc()),
      },
      where: 'scope = ? AND "key" = ?',
      whereArgs: <Object>[scope, key],
    );
  }
}
