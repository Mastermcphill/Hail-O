import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/moneybox_repository.dart';
import '../data/repositories/sqlite_moneybox_repository.dart';
import '../data/sqlite/dao/idempotency_dao.dart';
import '../data/sqlite/dao/moneybox_accounts_dao.dart';
import '../data/sqlite/dao/moneybox_ledger_dao.dart';
import '../domain/models/moneybox_account.dart';
import '../domain/models/moneybox_ledger_entry.dart';
import '../domain/services/finance_utils.dart';

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

    final repo = _moneyBoxRepositoryFor(db);
    final existing = await repo.getAccount(ownerId);
    if (existing == null) {
      await repo.upsertAccount(
        MoneyBoxAccount(
          ownerId: ownerId,
          tier: MoneyBoxTier.fromValue(safeTier),
          status: status,
          lockStart: lock,
          autoOpenDate: openDate,
          maturityDate: maturity,
          principalMinor: 0,
          projectedBonusMinor: 0,
          expectedAtMaturityMinor: 0,
          autosavePercent: safeAutosave,
          bonusEligible: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return getAccount(ownerId);
  }

  Future<Map<String, Object?>> getAccount(String ownerId) async {
    final repo = _moneyBoxRepositoryFor(db);
    final account = await repo.getAccount(ownerId);
    if (account != null) {
      return account.toMap();
    }
    return ensureAccount(ownerId: ownerId);
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

      final account = await _ensureAccountTx(txn, ownerId);
      final updated = MoneyBoxAccount(
        ownerId: account.ownerId,
        tier: account.tier,
        status: account.status,
        lockStart: account.lockStart,
        autoOpenDate: account.autoOpenDate,
        maturityDate: account.maturityDate,
        principalMinor: account.principalMinor,
        projectedBonusMinor: account.projectedBonusMinor,
        expectedAtMaturityMinor: account.expectedAtMaturityMinor,
        autosavePercent: safe,
        bonusEligible: account.bonusEligible,
        createdAt: account.createdAt,
        updatedAt: _nowUtc(),
      );
      await _moneyBoxRepositoryFor(txn).upsertAccount(updated);

      final result = <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'autosave_percent': safe,
        'status': updated.status,
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

      final account = await _ensureAccountTx(txn, ownerId);
      final principalAfter = account.principalMinor + amountMinor;
      final projectedBonusAfter = _projectedBonus(
        principalAfter,
        account.tier.value,
      );
      final expectedAfter = principalAfter + projectedBonusAfter;
      final now = _nowUtc();
      final repo = _moneyBoxRepositoryFor(txn);

      await repo.upsertAccount(
        MoneyBoxAccount(
          ownerId: account.ownerId,
          tier: account.tier,
          status: account.status,
          lockStart: account.lockStart,
          autoOpenDate: account.autoOpenDate,
          maturityDate: account.maturityDate,
          principalMinor: principalAfter,
          projectedBonusMinor: projectedBonusAfter,
          expectedAtMaturityMinor: expectedAfter,
          autosavePercent: account.autosavePercent,
          bonusEligible: account.bonusEligible,
          createdAt: account.createdAt,
          updatedAt: now,
        ),
      );

      await repo.appendLedger(
        MoneyBoxLedgerEntry(
          ownerId: ownerId,
          entryType: 'autosave_credit',
          amountMinor: amountMinor,
          principalAfterMinor: principalAfter,
          projectedBonusAfterMinor: projectedBonusAfter,
          expectedAfterMinor: expectedAfter,
          sourceKind: sourceKind,
          referenceId: referenceId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:moneybox_ledger',
          createdAt: now,
        ),
      );

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

  Future<MoneyBoxAccount> _ensureAccountTx(
    DatabaseExecutor txn,
    String ownerId,
  ) async {
    final repo = _moneyBoxRepositoryFor(txn);
    final existing = await repo.getAccount(ownerId);
    if (existing != null) {
      return existing;
    }

    final now = _nowUtc();
    final account = MoneyBoxAccount(
      ownerId: ownerId,
      tier: MoneyBoxTier.tier1,
      status: 'active',
      lockStart: now,
      autoOpenDate: now.add(const Duration(days: 29)),
      maturityDate: now.add(const Duration(days: 30)),
      principalMinor: 0,
      projectedBonusMinor: 0,
      expectedAtMaturityMinor: 0,
      autosavePercent: 0,
      bonusEligible: true,
      createdAt: now,
      updatedAt: now,
    );
    await repo.upsertAccount(account);
    return (await repo.getAccount(ownerId))!;
  }

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
  }

  Future<bool> _claimIdempotency(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
  }) async {
    final claim = await IdempotencyDao(txn).claim(scope: scope, key: key);
    return claim.isNewClaim;
  }

  Future<String> _readHash(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
  }) async {
    final record = await IdempotencyDao(txn).get(scope: scope, key: key);
    return record?.resultHash ?? '';
  }

  Future<void> _finalize(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
    required Map<String, Object?> result,
  }) async {
    final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
    await IdempotencyDao(
      txn,
    ).finalizeSuccess(scope: scope, key: key, resultHash: hash);
  }

  MoneyBoxRepository _moneyBoxRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteMoneyBoxRepository(
      accountsDao: MoneyBoxAccountsDao(txnOrDb),
      ledgerDao: MoneyBoxLedgerDao(txnOrDb),
    );
  }
}
