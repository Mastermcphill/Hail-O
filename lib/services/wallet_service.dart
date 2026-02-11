import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'finance_database.dart';

class WalletService {
  WalletService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final DateTime Function() _nowUtc;

  static const String _platformOwnerId = 'platform';

  Future<void> upsertUser({
    required String userId,
    required String role,
    String? fleetOwnerId,
  }) async {
    await db.transaction((txn) async {
      await _ensureUserTx(txn, userId: userId, role: role);
      if (role == 'driver') {
        await _ensureDriverProfileTx(
          txn,
          driverId: userId,
          fleetOwnerId: fleetOwnerId,
        );
      }
    });
  }

  Future<void> setFleetConfig({
    required String fleetOwnerId,
    required int allowancePercent,
  }) async {
    final now = isoNowUtc(_nowUtc());
    final safe = allowancePercent.clamp(0, 100);
    await db.transaction((txn) async {
      await _ensureUserTx(txn, userId: fleetOwnerId, role: 'fleet_owner');
      await txn.insert('fleet_configs', <String, Object?>{
        'fleet_owner_id': fleetOwnerId,
        'allowance_percent': safe,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int> getWalletBalanceMinor({
    required String ownerId,
    required WalletType walletType,
  }) async {
    final rows = await db.query(
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

  Future<Map<String, int>> getDriverWalletBalances(String driverId) async {
    final a = await getWalletBalanceMinor(
      ownerId: driverId,
      walletType: WalletType.driverA,
    );
    final b = await getWalletBalanceMinor(
      ownerId: driverId,
      walletType: WalletType.driverB,
    );
    final c = await getWalletBalanceMinor(
      ownerId: driverId,
      walletType: WalletType.driverC,
    );
    return <String, int>{
      'wallet_a_minor': a,
      'wallet_b_minor': b,
      'wallet_c_minor': c,
    };
  }

  Future<bool> isDriverBlockedByCashDebt(String driverId) async {
    final balances = await getDriverWalletBalances(driverId);
    return (balances['wallet_c_minor'] ?? 0) >
        (balances['wallet_a_minor'] ?? 0);
  }

  Future<Map<String, Object?>> openBidConnectionFeePaywall({
    required String rideId,
    required String riderId,
    required String driverId,
    required String tripScope,
    int? connectionFeeMinor,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final now = _nowUtc();
    final fee = connectionFeeMinor ?? _connectionFeeForScope(tripScope);
    final deadline = now.add(const Duration(minutes: 10));
    const scope = 'connection_fee_lock';

    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readIdempotencyHash(
          txn,
          scope: scope,
          key: idempotencyKey,
        );
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      await _ensureUserTx(txn, userId: riderId, role: 'rider');
      await _ensureUserTx(txn, userId: driverId, role: 'driver');
      await _ensureDriverProfileTx(txn, driverId: driverId);

      final nowIso = isoNowUtc(now);
      await txn.insert('rides', <String, Object?>{
        'id': rideId,
        'rider_id': riderId,
        'driver_id': driverId,
        'trip_scope': tripScope,
        'status': 'awaiting_connection_fee',
        'bidding_mode': 1,
        'connection_fee_minor': fee,
        'bid_accepted_at': nowIso,
        'connection_fee_deadline_at': isoNowUtc(deadline),
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final result = <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'connection_fee_minor': fee,
        'deadline_utc': isoNowUtc(deadline),
      };
      await _finalizeIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    });
  }

  Future<Map<String, Object?>> payConnectionFee({
    required String rideId,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    const scope = 'connection_fee_pay';
    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readIdempotencyHash(
          txn,
          scope: scope,
          key: idempotencyKey,
        );
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      final rows = await txn.query(
        'rides',
        where: 'id = ?',
        whereArgs: <Object>[rideId],
        limit: 1,
      );
      if (rows.isEmpty) {
        const result = <String, Object?>{
          'ok': false,
          'error': 'ride_not_found',
        };
        await _finalizeIdempotency(
          txn,
          scope: scope,
          key: idempotencyKey,
          result: result,
        );
        return result;
      }

      final row = rows.first;
      final status = (row['status'] as String?) ?? '';
      if (status == 'cancelled') {
        const result = <String, Object?>{
          'ok': false,
          'error': 'ride_cancelled',
        };
        await _finalizeIdempotency(
          txn,
          scope: scope,
          key: idempotencyKey,
          result: result,
        );
        return result;
      }

      if ((row['connection_fee_paid_at'] as String?) != null) {
        const result = <String, Object?>{'ok': true, 'already_paid': true};
        await _finalizeIdempotency(
          txn,
          scope: scope,
          key: idempotencyKey,
          result: result,
        );
        return result;
      }

      final deadlineRaw = (row['connection_fee_deadline_at'] as String?) ?? '';
      final deadline = DateTime.tryParse(deadlineRaw)?.toUtc();
      final now = _nowUtc();
      if (deadline == null || now.isAfter(deadline)) {
        await txn.update(
          'rides',
          <String, Object?>{
            'status': 'cancelled',
            'cancelled_at': isoNowUtc(now),
            'updated_at': isoNowUtc(now),
          },
          where: 'id = ?',
          whereArgs: <Object>[rideId],
        );
        const result = <String, Object?>{
          'ok': false,
          'error': 'connection_fee_timeout_auto_cancelled',
        };
        await _finalizeIdempotency(
          txn,
          scope: scope,
          key: idempotencyKey,
          result: result,
        );
        return result;
      }

      final fee = (row['connection_fee_minor'] as int?) ?? 0;
      final nowIso = isoNowUtc(now);
      await txn.update(
        'rides',
        <String, Object?>{
          'status': 'connection_fee_paid',
          'connection_fee_paid_at': nowIso,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[rideId],
      );

      if (fee > 0) {
        await _postWalletCreditTx(
          txn,
          ownerId: _platformOwnerId,
          walletType: WalletType.platform,
          amountMinor: fee,
          kind: 'connection_fee_non_refundable',
          referenceId: rideId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:platform_connection_fee',
        );
      }

      final result = <String, Object?>{
        'ok': true,
        'connection_fee_minor': fee,
        'ride_id': rideId,
      };
      await _finalizeIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    });
  }

  Future<int> autoCancelUnpaidConnectionFees({
    DateTime? nowUtc,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final now = nowUtc?.toUtc() ?? _nowUtc();
    const scope = 'connection_fee_auto_cancel';
    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        return 0;
      }

      final candidates = await txn.query(
        'rides',
        columns: <String>['id', 'connection_fee_deadline_at'],
        where: 'status = ? AND connection_fee_paid_at IS NULL',
        whereArgs: const <Object>['awaiting_connection_fee'],
      );

      var cancelled = 0;
      for (final row in candidates) {
        final rideId = (row['id'] as String?) ?? '';
        final deadlineRaw =
            (row['connection_fee_deadline_at'] as String?) ?? '';
        final deadline = DateTime.tryParse(deadlineRaw)?.toUtc();
        if (rideId.isEmpty || deadline == null || !now.isAfter(deadline)) {
          continue;
        }
        await txn.update(
          'rides',
          <String, Object?>{
            'status': 'cancelled',
            'cancelled_at': isoNowUtc(now),
            'updated_at': isoNowUtc(now),
          },
          where: 'id = ?',
          whereArgs: <Object>[rideId],
        );
        cancelled += 1;
      }

      await _finalizeIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
        result: <String, Object?>{'ok': true, 'cancelled': cancelled},
      );
      return cancelled;
    });
  }

  Future<Map<String, Object?>> settleRideFinance({
    required String rideId,
    required String driverId,
    required int baseFareMinor,
    required int premiumSeatMarkupMinor,
    required int cashCollectedMinor,
    String? fleetOwnerId,
    int? fleetAllowancePercent,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    const scope = 'settle_ride_finance';

    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        final hash = await _readIdempotencyHash(
          txn,
          scope: scope,
          key: idempotencyKey,
        );
        return <String, Object?>{
          'ok': true,
          'replayed': true,
          'result_hash': hash,
        };
      }

      await _ensureUserTx(txn, userId: driverId, role: 'driver');
      await _ensureDriverProfileTx(
        txn,
        driverId: driverId,
        fleetOwnerId: fleetOwnerId,
      );

      final effectiveFleetOwnerId = fleetOwnerId?.trim().isNotEmpty == true
          ? fleetOwnerId!.trim()
          : await _driverFleetOwnerTx(txn, driverId);

      if (effectiveFleetOwnerId != null) {
        await _ensureUserTx(
          txn,
          userId: effectiveFleetOwnerId,
          role: 'fleet_owner',
        );
      }

      final baseShare80 = percentOf(baseFareMinor, 80);
      final premiumToB = percentOf(premiumSeatMarkupMinor, 50);

      var driverAllowanceMinor = 0;
      if (effectiveFleetOwnerId != null) {
        if (baseShare80 > 0) {
          await _postWalletCreditTx(
            txn,
            ownerId: effectiveFleetOwnerId,
            walletType: WalletType.fleetOwner,
            amountMinor: baseShare80,
            kind: 'base_fare_80_share_fleet',
            referenceId: rideId,
            idempotencyScope: scope,
            idempotencyKey: '$idempotencyKey:fleet_owner_base_80',
          );
        }

        final allowance =
            fleetAllowancePercent ??
            await _fleetAllowancePercentTx(txn, effectiveFleetOwnerId);
        driverAllowanceMinor = percentOf(baseShare80, allowance);
        if (driverAllowanceMinor > 0) {
          await _postWalletCreditTx(
            txn,
            ownerId: driverId,
            walletType: WalletType.driverA,
            amountMinor: driverAllowanceMinor,
            kind: 'fleet_driver_allowance',
            referenceId: rideId,
            idempotencyScope: scope,
            idempotencyKey: '$idempotencyKey:driver_allowance',
          );
        }
      } else if (baseShare80 > 0) {
        await _postWalletCreditTx(
          txn,
          ownerId: driverId,
          walletType: WalletType.driverA,
          amountMinor: baseShare80,
          kind: 'base_fare_80_share',
          referenceId: rideId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:driver_base_80',
        );
      }

      if (premiumToB > 0) {
        await _postWalletCreditTx(
          txn,
          ownerId: driverId,
          walletType: WalletType.driverB,
          amountMinor: premiumToB,
          kind: 'premium_markup_50_locked',
          referenceId: rideId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:driver_premium_b',
        );
      }

      if (cashCollectedMinor > 0) {
        await _postWalletCreditTx(
          txn,
          ownerId: driverId,
          walletType: WalletType.driverC,
          amountMinor: cashCollectedMinor,
          kind: 'cash_debt_increase',
          referenceId: rideId,
          idempotencyScope: scope,
          idempotencyKey: '$idempotencyKey:driver_cash_debt',
        );
      }

      final walletA = await _walletBalanceTx(
        txn,
        ownerId: driverId,
        walletType: WalletType.driverA,
      );
      final walletC = await _walletBalanceTx(
        txn,
        ownerId: driverId,
        walletType: WalletType.driverC,
      );
      final blocked = walletC > walletA;
      await _upsertDriverBlockFlagTx(txn, driverId, blocked);
      await _upsertDriverCashDebtTx(txn, driverId, walletC);

      await _updateRideIfExistsTx(
        txn,
        rideId: rideId,
        baseFareMinor: baseFareMinor,
        premiumSeatMarkupMinor: premiumSeatMarkupMinor,
      );

      final result = <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'base_share_80_minor': baseShare80,
        'premium_to_wallet_b_minor': premiumToB,
        'driver_allowance_minor': driverAllowanceMinor,
        'wallet_a_minor': walletA,
        'wallet_c_minor': walletC,
        'driver_blocked': blocked,
      };
      await _finalizeIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    });
  }

  Future<int> moveWalletBToA({
    required String ownerId,
    required String idempotencyKey,
    String referenceId = 'monday_unlock',
  }) async {
    _requireIdempotency(idempotencyKey);
    const scope = 'wallet_b_to_a_move';

    return db.transaction((txn) async {
      final claimed = await _claimIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
      );
      if (!claimed) {
        return 0;
      }

      final bBalance = await _walletBalanceTx(
        txn,
        ownerId: ownerId,
        walletType: WalletType.driverB,
      );
      if (bBalance <= 0) {
        await _finalizeIdempotency(
          txn,
          scope: scope,
          key: idempotencyKey,
          result: <String, Object?>{'ok': true, 'moved_minor': 0},
        );
        return 0;
      }

      await _postWalletDebitTx(
        txn,
        ownerId: ownerId,
        walletType: WalletType.driverB,
        amountMinor: bBalance,
        kind: 'monday_unlock_transfer_out',
        referenceId: referenceId,
        idempotencyScope: scope,
        idempotencyKey: '$idempotencyKey:debit_b',
      );

      await _postWalletCreditTx(
        txn,
        ownerId: ownerId,
        walletType: WalletType.driverA,
        amountMinor: bBalance,
        kind: 'monday_unlock_transfer_in',
        referenceId: referenceId,
        idempotencyScope: scope,
        idempotencyKey: '$idempotencyKey:credit_a',
      );

      await _finalizeIdempotency(
        txn,
        scope: scope,
        key: idempotencyKey,
        result: <String, Object?>{'ok': true, 'moved_minor': bBalance},
      );
      return bBalance;
    });
  }

  Future<void> _ensureUserTx(
    Transaction txn, {
    required String userId,
    required String role,
  }) async {
    final now = isoNowUtc(_nowUtc());
    final rows = await txn.query(
      'users',
      columns: <String>['created_at'],
      where: 'id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await txn.insert('users', <String, Object?>{
        'id': userId,
        'role': role,
        'is_blocked': 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return;
    }

    await txn.update(
      'users',
      <String, Object?>{'role': role, 'updated_at': now},
      where: 'id = ?',
      whereArgs: <Object>[userId],
    );
  }

  Future<void> _ensureDriverProfileTx(
    Transaction txn, {
    required String driverId,
    String? fleetOwnerId,
  }) async {
    final now = isoNowUtc(_nowUtc());
    await txn.insert('driver_profiles', <String, Object?>{
      'driver_id': driverId,
      'fleet_owner_id': fleetOwnerId,
      'cash_debt_minor': 0,
      'safety_score': 0,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    if (fleetOwnerId?.trim().isNotEmpty == true) {
      await txn.update(
        'driver_profiles',
        <String, Object?>{
          'fleet_owner_id': fleetOwnerId!.trim(),
          'updated_at': now,
        },
        where: 'driver_id = ?',
        whereArgs: <Object>[driverId],
      );
    }
  }

  Future<void> _upsertDriverBlockFlagTx(
    Transaction txn,
    String driverId,
    bool blocked,
  ) async {
    final now = isoNowUtc(_nowUtc());
    final current = await txn.query(
      'users',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[driverId],
      limit: 1,
    );
    if (current.isEmpty) {
      await txn.insert('users', <String, Object?>{
        'id': driverId,
        'role': 'driver',
        'is_blocked': blocked ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return;
    }
    await txn.update(
      'users',
      <String, Object?>{'is_blocked': blocked ? 1 : 0, 'updated_at': now},
      where: 'id = ?',
      whereArgs: <Object>[driverId],
    );
  }

  Future<void> _upsertDriverCashDebtTx(
    Transaction txn,
    String driverId,
    int cashDebtMinor,
  ) async {
    final now = isoNowUtc(_nowUtc());
    await txn.update(
      'driver_profiles',
      <String, Object?>{'cash_debt_minor': cashDebtMinor, 'updated_at': now},
      where: 'driver_id = ?',
      whereArgs: <Object>[driverId],
    );
  }

  Future<void> _updateRideIfExistsTx(
    Transaction txn, {
    required String rideId,
    required int baseFareMinor,
    required int premiumSeatMarkupMinor,
  }) async {
    final rows = await txn.query(
      'rides',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[rideId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    await txn.update(
      'rides',
      <String, Object?>{
        'status': 'finance_settled',
        'base_fare_minor': baseFareMinor,
        'premium_markup_minor': premiumSeatMarkupMinor,
        'updated_at': isoNowUtc(_nowUtc()),
      },
      where: 'id = ?',
      whereArgs: <Object>[rideId],
    );
  }

  Future<String?> _driverFleetOwnerTx(Transaction txn, String driverId) async {
    final rows = await txn.query(
      'driver_profiles',
      columns: <String>['fleet_owner_id'],
      where: 'driver_id = ?',
      whereArgs: <Object>[driverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final value = (rows.first['fleet_owner_id'] as String?)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<int> _fleetAllowancePercentTx(
    Transaction txn,
    String fleetOwnerId,
  ) async {
    final rows = await txn.query(
      'fleet_configs',
      columns: <String>['allowance_percent'],
      where: 'fleet_owner_id = ?',
      whereArgs: <Object>[fleetOwnerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return ((rows.first['allowance_percent'] as int?) ?? 0).clamp(0, 100);
  }

  Future<void> _ensureWalletTx(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final now = isoNowUtc(_nowUtc());
    await txn.insert('wallets', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.value,
      'balance_minor': 0,
      'reserved_minor': 0,
      'currency': 'NGN',
      'created_at': now,
      'updated_at': now,
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
    if (amountMinor <= 0) {
      return _walletBalanceTx(txn, ownerId: ownerId, walletType: walletType);
    }

    final current = await _walletBalanceTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    final next = current + amountMinor;
    final now = isoNowUtc(_nowUtc());

    await txn.update(
      'wallets',
      <String, Object?>{'balance_minor': next, 'updated_at': now},
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
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return next;
  }

  Future<int> _postWalletDebitTx(
    Transaction txn, {
    required String ownerId,
    required WalletType walletType,
    required int amountMinor,
    required String kind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    if (amountMinor <= 0) {
      return _walletBalanceTx(txn, ownerId: ownerId, walletType: walletType);
    }
    final current = await _walletBalanceTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    if (current < amountMinor) {
      throw StateError(
        'insufficient_funds_for_debit:$ownerId:${walletType.value}',
      );
    }
    final next = current - amountMinor;
    final now = isoNowUtc(_nowUtc());

    await txn.update(
      'wallets',
      <String, Object?>{'balance_minor': next, 'updated_at': now},
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.value],
    );

    await txn.insert('wallet_ledger', <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.value,
      'direction': 'debit',
      'amount_minor': amountMinor,
      'balance_after_minor': next,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': now,
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

  Future<String> _readIdempotencyHash(
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

  Future<void> _finalizeIdempotency(
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

  int _connectionFeeForScope(String scopeRaw) {
    final scope = scopeRaw.trim().toLowerCase();
    if (scope == 'cross_country' || scope == 'international') {
      return 20000;
    }
    if (scope == 'inter_state') {
      return 10000;
    }
    return 5000;
  }
}
