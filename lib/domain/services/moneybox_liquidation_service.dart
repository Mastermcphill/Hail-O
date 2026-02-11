import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../models/wallet.dart';

class MoneyBoxLiquidationService {
  MoneyBoxLiquidationService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeLiquidateSuspension =
      'moneybox.liquidate.suspension';
  static const String _scopeLiquidateDispute = 'moneybox.liquidate.dispute';

  Future<Map<String, Object?>> liquidateOnSuspensionOrBan({
    required String ownerId,
    required String reason,
    WalletType destinationWalletType = WalletType.driverA,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final claim = await _idempotencyStore.claim(
      scope: _scopeLiquidateSuspension,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final now = _nowUtc();
    final result = await db.transaction((txn) async {
      final account = await _readMoneyBoxAccount(txn, ownerId);
      final principal = (account['principal_minor'] as int?) ?? 0;
      if (principal <= 0) {
        final noFundsResult = <String, Object?>{
          'ok': true,
          'owner_id': ownerId,
          'liquidated_minor': 0,
          'status': 'no_funds',
        };
        await _recordLiquidationEvent(
          txn,
          eventId: '$ownerId:${now.microsecondsSinceEpoch}',
          ownerId: ownerId,
          reason: reason,
          principalMinor: 0,
          penaltyMinor: 0,
          harmedPartyId: null,
          status: 'no_funds',
          scope: _scopeLiquidateSuspension,
          key: idempotencyKey,
          createdAt: now,
        );
        return noFundsResult;
      }

      await _writeMoneyboxOutLedger(
        txn,
        ownerId: ownerId,
        amountMinor: principal,
        entryType: 'liquidate_out',
        sourceKind: 'system_suspension_or_ban',
        referenceId: reason,
        idempotencyScope: _scopeLiquidateSuspension,
        idempotencyKey: '$idempotencyKey:moneybox',
        createdAt: now,
        principalAfterMinor: 0,
      );

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'principal_minor': 0,
          'projected_bonus_minor': 0,
          'expected_at_maturity_minor': 0,
          'status': 'liquidated',
          'updated_at': _iso(now),
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      final walletBalanceAfter = await _creditWallet(
        txn,
        ownerId: ownerId,
        walletType: destinationWalletType,
        amountMinor: principal,
        kind: 'moneybox_liquidation_credit',
        referenceId: reason,
        idempotencyScope: _scopeLiquidateSuspension,
        idempotencyKey: '$idempotencyKey:wallet',
        createdAt: now,
      );

      await _recordLiquidationEvent(
        txn,
        eventId: '$ownerId:${now.microsecondsSinceEpoch}',
        ownerId: ownerId,
        reason: reason,
        principalMinor: principal,
        penaltyMinor: 0,
        harmedPartyId: null,
        status: 'completed',
        scope: _scopeLiquidateSuspension,
        key: idempotencyKey,
        createdAt: now,
      );

      return <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'liquidated_minor': principal,
        'wallet_balance_after_minor': walletBalanceAfter,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeLiquidateSuspension,
      key: idempotencyKey,
      resultHash: _hashResult(result),
    );
    return result;
  }

  Future<Map<String, Object?>> liquidateForDisputeGuilty({
    required String ownerId,
    required String harmedPartyId,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final claim = await _idempotencyStore.claim(
      scope: _scopeLiquidateDispute,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final now = _nowUtc();
    final result = await db.transaction((txn) async {
      final account = await _readMoneyBoxAccount(txn, ownerId);
      final principal = (account['principal_minor'] as int?) ?? 0;
      final requestedPenalty = (principal * 10) ~/ 100;
      final ownerWalletBalance = await _ensureWalletAndGetBalance(
        txn,
        ownerId: ownerId,
        walletType: WalletType.driverA,
      );
      final recoveredPenalty = requestedPenalty > ownerWalletBalance
          ? ownerWalletBalance
          : requestedPenalty;
      final recoveredTotal = principal + recoveredPenalty;

      if (principal > 0) {
        await _writeMoneyboxOutLedger(
          txn,
          ownerId: ownerId,
          amountMinor: principal,
          entryType: 'dispute_recovery_out',
          sourceKind: 'system_dispute_guilty',
          referenceId: harmedPartyId,
          idempotencyScope: _scopeLiquidateDispute,
          idempotencyKey: '$idempotencyKey:moneybox',
          createdAt: now,
          principalAfterMinor: 0,
        );
      }

      await txn.update(
        'moneybox_accounts',
        <String, Object?>{
          'principal_minor': 0,
          'projected_bonus_minor': 0,
          'expected_at_maturity_minor': 0,
          'status': 'dispute_liquidated',
          'updated_at': _iso(now),
        },
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
      );

      if (recoveredPenalty > 0) {
        await _debitWallet(
          txn,
          ownerId: ownerId,
          walletType: WalletType.driverA,
          amountMinor: recoveredPenalty,
          kind: 'moneybox_dispute_penalty_debit',
          referenceId: harmedPartyId,
          idempotencyScope: _scopeLiquidateDispute,
          idempotencyKey: '$idempotencyKey:penalty_debit',
          createdAt: now,
        );
      }

      final harmedBalanceAfter = await _creditWallet(
        txn,
        ownerId: harmedPartyId,
        walletType: WalletType.driverA,
        amountMinor: recoveredTotal,
        kind: 'moneybox_dispute_recovery_credit',
        referenceId: ownerId,
        idempotencyScope: _scopeLiquidateDispute,
        idempotencyKey: '$idempotencyKey:harmed_credit',
        createdAt: now,
      );

      await _recordLiquidationEvent(
        txn,
        eventId: '$ownerId:$harmedPartyId:${now.microsecondsSinceEpoch}',
        ownerId: ownerId,
        reason: 'money_dispute_guilty',
        principalMinor: principal,
        penaltyMinor: recoveredPenalty,
        harmedPartyId: harmedPartyId,
        status: 'completed',
        scope: _scopeLiquidateDispute,
        key: idempotencyKey,
        createdAt: now,
      );

      return <String, Object?>{
        'ok': true,
        'owner_id': ownerId,
        'harmed_party_id': harmedPartyId,
        'principal_recovered_minor': principal,
        'penalty_recovered_minor': recoveredPenalty,
        'total_credited_minor': recoveredTotal,
        'harmed_wallet_balance_after_minor': harmedBalanceAfter,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeLiquidateDispute,
      key: idempotencyKey,
      resultHash: _hashResult(result),
    );
    return result;
  }

  Future<Map<String, Object?>> _readMoneyBoxAccount(
    Transaction txn,
    String ownerId,
  ) async {
    final rows = await txn.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Map<String, Object?>.from(rows.first);
    }

    final now = _nowUtc();
    await txn.insert('moneybox_accounts', <String, Object?>{
      'owner_id': ownerId,
      'tier': 1,
      'status': 'locked',
      'lock_start': _iso(now),
      'auto_open_date': _iso(now.add(const Duration(days: 29))),
      'maturity_date': _iso(now.add(const Duration(days: 30))),
      'principal_minor': 0,
      'projected_bonus_minor': 0,
      'expected_at_maturity_minor': 0,
      'autosave_percent': 0,
      'bonus_eligible': 1,
      'created_at': _iso(now),
      'updated_at': _iso(now),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final inserted = await txn.query(
      'moneybox_accounts',
      where: 'owner_id = ?',
      whereArgs: <Object>[ownerId],
      limit: 1,
    );
    return Map<String, Object?>.from(inserted.first);
  }

  Future<int> _ensureWalletAndGetBalance(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final now = _iso(_nowUtc());
    await txn.insert('wallets', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.dbValue,
      'balance_minor': 0,
      'reserved_minor': 0,
      'currency': 'NGN',
      'updated_at': now,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await txn.query(
      'wallets',
      columns: <String>['balance_minor'],
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
      limit: 1,
    );
    return (rows.first['balance_minor'] as int?) ?? 0;
  }

  Future<int> _creditWallet(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
    required int amountMinor,
    required String kind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  }) async {
    final current = await _ensureWalletAndGetBalance(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    final next = current + amountMinor;
    await txn.update(
      'wallets',
      <String, Object?>{'balance_minor': next, 'updated_at': _iso(createdAt)},
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
    );
    await txn.insert('wallet_ledger', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.dbValue,
      'direction': 'credit',
      'amount_minor': amountMinor,
      'balance_after_minor': next,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': _iso(createdAt),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return next;
  }

  Future<int> _debitWallet(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
    required int amountMinor,
    required String kind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  }) async {
    final current = await _ensureWalletAndGetBalance(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    final next = current - amountMinor;
    if (next < 0) {
      throw StateError('insufficient_funds:$ownerId:${walletType.dbValue}');
    }
    await txn.update(
      'wallets',
      <String, Object?>{'balance_minor': next, 'updated_at': _iso(createdAt)},
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
    );
    await txn.insert('wallet_ledger', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.dbValue,
      'direction': 'debit',
      'amount_minor': amountMinor,
      'balance_after_minor': next,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': _iso(createdAt),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return next;
  }

  Future<void> _writeMoneyboxOutLedger(
    Transaction txn, {
    required String ownerId,
    required int amountMinor,
    required int principalAfterMinor,
    required String entryType,
    required String sourceKind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  }) async {
    await txn.insert('moneybox_ledger', <String, Object?>{
      'owner_id': ownerId,
      'entry_type': entryType,
      'amount_minor': amountMinor,
      'principal_after_minor': principalAfterMinor,
      'projected_bonus_after_minor': 0,
      'expected_after_minor': principalAfterMinor,
      'source_kind': sourceKind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': _iso(createdAt),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> _recordLiquidationEvent(
    Transaction txn, {
    required String eventId,
    required String ownerId,
    required String reason,
    required int principalMinor,
    required int penaltyMinor,
    required String? harmedPartyId,
    required String status,
    required String scope,
    required String key,
    required DateTime createdAt,
  }) async {
    await txn.insert('moneybox_liquidation_events', <String, Object?>{
      'event_id': eventId,
      'owner_id': ownerId,
      'reason': reason,
      'principal_minor': principalMinor,
      'penalty_minor': penaltyMinor,
      'harmed_party_id': harmedPartyId,
      'status': status,
      'idempotency_scope': scope,
      'idempotency_key': key,
      'created_at': _iso(createdAt),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hashResult(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotency key is required');
    }
  }
}
