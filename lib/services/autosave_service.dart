import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'finance_database.dart';
import 'moneybox_service.dart';

class AutosaveService {
  AutosaveService(
    this.db, {
    required this.moneyBoxService,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final MoneyBoxService moneyBoxService;
  final DateTime Function() _nowUtc;

  static const String confirmedCommissionCredit = 'confirmed_commission_credit';

  Future<Map<String, Object?>> applyOnConfirmedCommissionCredit({
    required String ownerId,
    required WalletType destinationWalletType,
    required int grossAmountMinor,
    required String sourceKind,
    required String referenceId,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    if (grossAmountMinor <= 0) {
      throw ArgumentError('grossAmountMinor must be > 0');
    }
    if (sourceKind != confirmedCommissionCredit) {
      return <String, Object?>{
        'ok': false,
        'error': 'autosave_source_not_allowed',
      };
    }

    const scope = 'autosave_split_credit';
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

      await _ensureMoneyBoxAccountTx(txn, ownerId);
      final account = await _moneyBoxAccountTx(txn, ownerId);

      final autosavePercent = ((account['autosave_percent'] as int?) ?? 0)
          .clamp(0, 30);
      final tier = (account['tier'] as int?) ?? 1;
      final principalBefore = (account['principal_minor'] as int?) ?? 0;

      final savedMinor = autosavePercent >= 1
          ? percentOf(grossAmountMinor, autosavePercent)
          : 0;
      final remainderMinor = grossAmountMinor - savedMinor;
      final nowIso = isoNowUtc(_nowUtc());

      var principalAfter = principalBefore;
      var projectedBonusAfter = (account['projected_bonus_minor'] as int?) ?? 0;
      var expectedAfter = (account['expected_at_maturity_minor'] as int?) ?? 0;

      if (savedMinor > 0) {
        principalAfter = principalBefore + savedMinor;
        projectedBonusAfter = moneyBoxService.projectedBonusFor(
          principalMinor: principalAfter,
          tier: tier,
        );
        expectedAfter = principalAfter + projectedBonusAfter;

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
          'amount_minor': savedMinor,
          'principal_after_minor': principalAfter,
          'projected_bonus_after_minor': projectedBonusAfter,
          'expected_after_minor': expectedAfter,
          'source_kind': sourceKind,
          'reference_id': referenceId,
          'idempotency_scope': scope,
          'idempotency_key': '$idempotencyKey:moneybox',
          'created_at': nowIso,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      var walletBalanceAfter = await _walletBalanceTx(
        txn,
        ownerId: ownerId,
        walletType: destinationWalletType,
      );
      if (remainderMinor > 0) {
        walletBalanceAfter = await _postWalletCreditTx(
          txn,
          ownerId: ownerId,
          walletType: destinationWalletType,
          amountMinor: remainderMinor,
          kind: confirmedCommissionCredit,
          referenceId: referenceId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:wallet',
        );
      }

      final result = <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'gross_minor': grossAmountMinor,
        'saved_minor': savedMinor,
        'remainder_minor': remainderMinor,
        'autosave_percent': autosavePercent,
        'wallet_balance_after_minor': walletBalanceAfter,
        'moneybox_principal_after_minor': principalAfter,
        'moneybox_projected_bonus_after_minor': projectedBonusAfter,
        'moneybox_expected_after_minor': expectedAfter,
      };

      await _finalize(txn, scope: scope, key: idempotencyKey, result: result);
      return result;
    });
  }

  Future<void> _ensureMoneyBoxAccountTx(Transaction txn, String ownerId) async {
    final now = _nowUtc();
    final nowIso = isoNowUtc(now);
    await txn.insert('moneybox_accounts', <String, Object?>{
      'owner_id': ownerId,
      'tier': 1,
      'lock_start': nowIso,
      'auto_open_date': isoNowUtc(now.add(const Duration(days: 29))),
      'maturity_date': isoNowUtc(now.add(const Duration(days: 30))),
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

  Future<Map<String, Object?>> _moneyBoxAccountTx(
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

  Future<void> _ensureWalletTx(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final nowIso = isoNowUtc(_nowUtc());
    await txn.insert('wallets', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.value,
      'balance_minor': 0,
      'reserved_minor': 0,
      'currency': 'NGN',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> _walletBalanceTx(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    await _ensureWalletTx(txn, ownerId: ownerId, walletType: walletType);
    final rows = await txn.query(
      'wallets',
      columns: <String>['balance_minor'],
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.value],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['balance_minor'] as int?) ?? 0;
  }

  Future<int> _postWalletCreditTx(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
    required int amountMinor,
    required String kind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final current = await _walletBalanceTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    final next = current + amountMinor;
    final nowIso = isoNowUtc(_nowUtc());

    await txn.update(
      'wallets',
      <String, Object?>{'balance_minor': next, 'updated_at': nowIso},
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.value],
    );

    await txn.insert('wallet_ledger', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.value,
      'direction': 'credit',
      'amount_minor': amountMinor,
      'balance_after_minor': next,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return next;
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
