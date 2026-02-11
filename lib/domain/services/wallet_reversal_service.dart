import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/wallet_reversals_dao.dart';
import '../models/idempotency_record.dart';
import '../models/wallet_reversal_record.dart';
import 'finance_utils.dart';

class WalletReversalService {
  WalletReversalService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeWalletReversal = 'wallet_reversal';

  Future<Map<String, Object?>> reverseWalletLedgerEntry({
    required int originalLedgerId,
    required String requestedByUserId,
    required bool requesterIsAdmin,
    required String reason,
    required String idempotencyKey,
    int? reversalAmountMinor,
  }) async {
    if (!requesterIsAdmin) {
      throw StateError('reversal_forbidden');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('reason is required');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeWalletReversal,
      key: idempotencyKey,
      requestHash:
          '$originalLedgerId|$requestedByUserId|$reason|${reversalAmountMinor ?? 0}',
    );
    if (!claim.isNewClaim) {
      return _buildReplayResponse(claim.record, idempotencyKey);
    }

    try {
      final now = _nowUtc();
      final nowIso = isoNowUtc(now);
      final result = await db.transaction((txn) async {
        final reversalsDao = WalletReversalsDao(txn);
        final existing = await reversalsDao.findByOriginalLedgerId(
          originalLedgerId,
        );
        if (existing != null) {
          return _loadExistingReversalResult(txn, existing, replayed: true);
        }

        final originalRows = await txn.query(
          'wallet_ledger',
          where: 'id = ?',
          whereArgs: <Object>[originalLedgerId],
          limit: 1,
        );
        if (originalRows.isEmpty) {
          return <String, Object?>{
            'ok': false,
            'error': 'original_ledger_not_found',
          };
        }
        final original = originalRows.first;
        final ownerId = (original['owner_id'] as String?) ?? '';
        final walletType = (original['wallet_type'] as String?) ?? '';
        final originalDirection = (original['direction'] as String?) ?? '';
        final originalAmountMinor =
            (original['amount_minor'] as num?)?.toInt() ?? 0;
        final amountMinor = reversalAmountMinor ?? originalAmountMinor;
        final originalKind = (original['kind'] as String?) ?? 'unknown';
        final referenceId =
            (original['reference_id'] as String?) ?? 'reversal_reference';

        if (ownerId.isEmpty ||
            walletType.isEmpty ||
            originalAmountMinor <= 0 ||
            amountMinor <= 0 ||
            amountMinor > originalAmountMinor) {
          return <String, Object?>{
            'ok': false,
            'error': 'invalid_original_ledger_row',
          };
        }

        await txn.insert('wallets', <String, Object?>{
          'owner_id': ownerId,
          'wallet_type': walletType,
          'balance_minor': 0,
          'reserved_minor': 0,
          'currency': 'NGN',
          'updated_at': nowIso,
          'created_at': nowIso,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        final walletRows = await txn.query(
          'wallets',
          columns: <String>['balance_minor'],
          where: 'owner_id = ? AND wallet_type = ?',
          whereArgs: <Object>[ownerId, walletType],
          limit: 1,
        );
        final currentBalance =
            (walletRows.first['balance_minor'] as num?)?.toInt() ?? 0;

        final reversalDirection = originalDirection == 'credit'
            ? 'debit'
            : 'credit';
        final nextBalance = reversalDirection == 'credit'
            ? currentBalance + amountMinor
            : currentBalance - amountMinor;
        if (nextBalance < 0) {
          return <String, Object?>{
            'ok': false,
            'error': 'insufficient_balance_for_reversal',
          };
        }

        await txn.update(
          'wallets',
          <String, Object?>{'balance_minor': nextBalance, 'updated_at': nowIso},
          where: 'owner_id = ? AND wallet_type = ?',
          whereArgs: <Object>[ownerId, walletType],
        );

        final reversalLedgerId = await txn
            .insert('wallet_ledger', <String, Object?>{
              'owner_id': ownerId,
              'wallet_type': walletType,
              'direction': reversalDirection,
              'amount_minor': amountMinor,
              'balance_after_minor': nextBalance,
              'kind': 'reversal:$originalKind',
              'reference_id': 'reversal:$referenceId',
              'idempotency_scope': _scopeWalletReversal,
              'idempotency_key': '$idempotencyKey:ledger',
              'created_at': nowIso,
            }, conflictAlgorithm: ConflictAlgorithm.abort);

        final reversalRecord = WalletReversalRecord(
          id: 'reversal:$originalLedgerId',
          originalLedgerId: originalLedgerId,
          reversalLedgerId: reversalLedgerId,
          requestedByUserId: requestedByUserId,
          reason: reason.trim(),
          idempotencyScope: _scopeWalletReversal,
          idempotencyKey: idempotencyKey,
          createdAt: now,
        );
        await reversalsDao.insert(reversalRecord, viaOrchestrator: true);

        return <String, Object?>{
          'ok': true,
          'replayed': false,
          'owner_id': ownerId,
          'wallet_type': walletType,
          'original_ledger_id': originalLedgerId,
          'reversal_ledger_id': reversalLedgerId,
          'amount_minor': amountMinor,
          'original_amount_minor': originalAmountMinor,
          'balance_after_minor': nextBalance,
          'direction': reversalDirection,
        };
      });

      if (result['ok'] != true) {
        await _idempotencyStore.finalizeFailure(
          scope: _scopeWalletReversal,
          key: idempotencyKey,
          errorCode: (result['error'] as String?) ?? 'wallet_reversal_failed',
        );
        return result;
      }

      final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeWalletReversal,
        key: idempotencyKey,
        resultHash: hash,
      );
      return <String, Object?>{...result, 'result_hash': hash};
    } catch (_) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeWalletReversal,
        key: idempotencyKey,
        errorCode: 'wallet_reversal_exception',
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _buildReplayResponse(
    IdempotencyRecord record,
    String idempotencyKey,
  ) async {
    if (record.status == IdempotencyStatus.success) {
      final reversal = await WalletReversalsDao(db).findByIdempotency(
        idempotencyScope: _scopeWalletReversal,
        idempotencyKey: idempotencyKey,
      );
      if (reversal != null) {
        return _loadExistingReversalResult(db, reversal, replayed: true);
      }
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': record.resultHash,
      };
    }
    return <String, Object?>{
      'ok': false,
      'replayed': true,
      'error': record.errorCode ?? 'wallet_reversal_failed',
    };
  }

  Future<Map<String, Object?>> _loadExistingReversalResult(
    DatabaseExecutor executor,
    WalletReversalRecord reversal, {
    required bool replayed,
  }) async {
    final ledgerRows = await executor.query(
      'wallet_ledger',
      where: 'id = ?',
      whereArgs: <Object>[reversal.reversalLedgerId],
      limit: 1,
    );
    if (ledgerRows.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'replayed': replayed,
        'error': 'reversal_ledger_not_found',
      };
    }
    final row = ledgerRows.first;
    return <String, Object?>{
      'ok': true,
      'replayed': replayed,
      'owner_id': row['owner_id'],
      'wallet_type': row['wallet_type'],
      'original_ledger_id': reversal.originalLedgerId,
      'reversal_ledger_id': reversal.reversalLedgerId,
      'amount_minor': row['amount_minor'],
      'balance_after_minor': row['balance_after_minor'],
      'direction': row['direction'],
    };
  }
}
