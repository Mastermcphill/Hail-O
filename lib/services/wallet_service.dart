import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/sqlite_wallet_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/sqlite/dao/driver_profiles_dao.dart';
import '../data/sqlite/dao/fleet_configs_dao.dart';
import '../data/sqlite/dao/idempotency_dao.dart';
import '../data/sqlite/dao/rides_dao.dart';
import '../data/sqlite/dao/users_dao.dart';
import '../data/sqlite/dao/wallet_ledger_dao.dart';
import '../data/sqlite/dao/wallets_dao.dart';
import '../domain/models/driver_profile.dart';
import '../domain/models/user.dart';
import '../domain/models/wallet.dart';
import '../domain/models/wallet_ledger_entry.dart';
import '../domain/services/cancel_ride_service.dart';
import '../domain/services/finance_utils.dart';

class WalletService {
  WalletService(
    this.db, {
    DateTime Function()? nowUtc,
    CancelRideService? cancelRideService,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _cancelRideService = cancelRideService;

  final Database db;
  final DateTime Function() _nowUtc;
  final CancelRideService? _cancelRideService;

  static const String _platformOwnerId = 'platform';
  late final CancelRideService _resolvedCancelRideService =
      _cancelRideService ?? CancelRideService(db, nowUtc: _nowUtc);

  Future<void> upsertUser({
    required String userId,
    required String role,
    String? fleetOwnerId,
  }) async {
    await db.transaction((txn) async {
      await _ensureUserTx(txn, userId: userId, role: role);
      if (role == UserRole.driver.dbValue) {
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
      await _ensureUserTx(
        txn,
        userId: fleetOwnerId,
        role: UserRole.fleetOwner.dbValue,
      );
      await FleetConfigsDao(
        txn,
      ).upsert(fleetOwnerId: fleetOwnerId, allowancePercent: safe, nowIso: now);
    });
  }

  Future<int> getWalletBalanceMinor({
    required String ownerId,
    required WalletType walletType,
  }) async {
    final wallet = await _walletRepositoryFor(
      db,
    ).getWallet(ownerId, walletType);
    return wallet?.balanceMinor ?? 0;
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

      await _ensureUserTx(txn, userId: riderId, role: UserRole.rider.dbValue);
      await _ensureUserTx(txn, userId: driverId, role: UserRole.driver.dbValue);
      await _ensureDriverProfileTx(txn, driverId: driverId);

      final nowIso = isoNowUtc(now);
      await RidesDao(txn).upsertAwaitingConnectionFee(
        rideId: rideId,
        riderId: riderId,
        driverId: driverId,
        tripScope: tripScope,
        feeMinor: fee,
        bidAcceptedAtIso: nowIso,
        feeDeadlineAtIso: isoNowUtc(deadline),
        nowIso: nowIso,
      );

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
    final claimed = await _claimIdempotency(
      db,
      scope: scope,
      key: idempotencyKey,
    );
    if (!claimed) {
      final hash = await _readIdempotencyHash(
        db,
        scope: scope,
        key: idempotencyKey,
      );
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': hash,
      };
    }

    final ride = await RidesDao(db).findById(rideId);
    if (ride == null) {
      const result = <String, Object?>{'ok': false, 'error': 'ride_not_found'};
      await _finalizeIdempotency(
        db,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    }

    final status = (ride['status'] as String?) ?? '';
    if (status == 'cancelled') {
      const result = <String, Object?>{'ok': false, 'error': 'ride_cancelled'};
      await _finalizeIdempotency(
        db,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    }

    if ((ride['connection_fee_paid_at'] as String?) != null) {
      const result = <String, Object?>{'ok': true, 'already_paid': true};
      await _finalizeIdempotency(
        db,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    }

    final deadlineRaw = (ride['connection_fee_deadline_at'] as String?) ?? '';
    final deadline = DateTime.tryParse(deadlineRaw)?.toUtc();
    final now = _nowUtc();
    if (deadline == null || now.isAfter(deadline)) {
      final riderId = ((ride['rider_id'] as String?) ?? '').trim();
      final driverId = ((ride['driver_id'] as String?) ?? '').trim();
      final payerUserId = riderId.isNotEmpty ? riderId : driverId;
      if (payerUserId.isNotEmpty) {
        await _resolvedCancelRideService.collectCancellationPenalty(
          rideId: rideId,
          payerUserId: payerUserId,
          penaltyMinor: 0,
          idempotencyKey: 'connection_fee_timeout:$rideId',
          ruleCode: 'connection_fee_timeout_auto_cancelled',
          rideType: (ride['trip_scope'] as String?)?.trim(),
          totalFareMinor: (ride['total_fare_minor'] as num?)?.toInt() ?? 0,
          cancelledAt: now,
        );
      }
      const result = <String, Object?>{
        'ok': false,
        'error': 'connection_fee_timeout_auto_cancelled',
      };
      await _finalizeIdempotency(
        db,
        scope: scope,
        key: idempotencyKey,
        result: result,
      );
      return result;
    }

    final fee = (ride['connection_fee_minor'] as int?) ?? 0;
    final nowIso = isoNowUtc(now);
    await db.transaction((txn) async {
      await RidesDao(txn).markConnectionFeePaid(rideId: rideId, nowIso: nowIso);

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
    });

    final result = <String, Object?>{
      'ok': true,
      'connection_fee_minor': fee,
      'ride_id': rideId,
    };
    await _finalizeIdempotency(
      db,
      scope: scope,
      key: idempotencyKey,
      result: result,
    );
    return result;
  }

  Future<int> autoCancelUnpaidConnectionFees({
    DateTime? nowUtc,
    required String idempotencyKey,
  }) async {
    _requireIdempotency(idempotencyKey);
    final now = nowUtc?.toUtc() ?? _nowUtc();
    const scope = 'connection_fee_auto_cancel';
    final claimed = await _claimIdempotency(
      db,
      scope: scope,
      key: idempotencyKey,
    );
    if (!claimed) {
      return 0;
    }

    final candidates = await RidesDao(
      db,
    ).listAwaitingConnectionFeeWithoutPayment();

    var cancelled = 0;
    for (final row in candidates) {
      final rideId = (row['id'] as String?) ?? '';
      final deadlineRaw = (row['connection_fee_deadline_at'] as String?) ?? '';
      final deadline = DateTime.tryParse(deadlineRaw)?.toUtc();
      if (rideId.isEmpty || deadline == null || !now.isAfter(deadline)) {
        continue;
      }

      final ride = await RidesDao(db).findById(rideId);
      if (ride == null) {
        continue;
      }
      final riderId = ((ride['rider_id'] as String?) ?? '').trim();
      final driverId = ((ride['driver_id'] as String?) ?? '').trim();
      final payerUserId = riderId.isNotEmpty ? riderId : driverId;
      if (payerUserId.isEmpty) {
        continue;
      }

      final cancellation = await _resolvedCancelRideService
          .collectCancellationPenalty(
            rideId: rideId,
            payerUserId: payerUserId,
            penaltyMinor: 0,
            idempotencyKey: 'connection_fee_auto_cancel:$rideId',
            ruleCode: 'connection_fee_timeout_auto_cancelled',
            rideType: (ride['trip_scope'] as String?)?.trim(),
            totalFareMinor: (ride['total_fare_minor'] as num?)?.toInt() ?? 0,
            cancelledAt: now,
          );
      if (cancellation.ok && !cancellation.replayed) {
        cancelled += 1;
      }
    }

    await _finalizeIdempotency(
      db,
      scope: scope,
      key: idempotencyKey,
      result: <String, Object?>{'ok': true, 'cancelled': cancelled},
    );
    return cancelled;
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

      await _ensureUserTx(txn, userId: driverId, role: UserRole.driver.dbValue);
      await _ensureDriverProfileTx(
        txn,
        driverId: driverId,
        fleetOwnerId: fleetOwnerId,
      );

      final effectiveFleetOwnerId = fleetOwnerId?.trim().isNotEmpty == true
          ? fleetOwnerId!.trim()
          : await _driverFleetOwnerTx(txn, driverId);

      final baseShare80 = percentOf(baseFareMinor, 80);
      final premiumToB = percentOf(premiumSeatMarkupMinor, 50);

      var driverAllowanceMinor = 0;
      if (effectiveFleetOwnerId != null) {
        await _ensureUserTx(
          txn,
          userId: effectiveFleetOwnerId,
          role: UserRole.fleetOwner.dbValue,
        );
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

      await RidesDao(txn).updateFinanceIfExists(
        rideId: rideId,
        baseFareMinor: baseFareMinor,
        premiumSeatMarkupMinor: premiumSeatMarkupMinor,
        nowIso: isoNowUtc(_nowUtc()),
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
    DatabaseExecutor txn, {
    required String userId,
    required String role,
  }) async {
    final usersDao = UsersDao(txn);
    final existing = await usersDao.findById(userId);
    final now = _nowUtc();
    final targetRole = UserRole.fromDbValue(role);

    if (existing == null) {
      await usersDao.insert(
        User(id: userId, role: targetRole, createdAt: now, updatedAt: now),
      );
      return;
    }

    await usersDao.update(
      User(
        id: existing.id,
        role: targetRole,
        email: existing.email,
        displayName: existing.displayName,
        gender: existing.gender,
        tribe: existing.tribe,
        starRating: existing.starRating,
        luggageCount: existing.luggageCount,
        nextOfKinLocked: existing.nextOfKinLocked,
        crossBorderDocLocked: existing.crossBorderDocLocked,
        allowLocationOff: existing.allowLocationOff,
        isBlocked: existing.isBlocked,
        disclosureAccepted: existing.disclosureAccepted,
        createdAt: existing.createdAt,
        updatedAt: now,
      ),
    );
  }

  Future<void> _ensureDriverProfileTx(
    DatabaseExecutor txn, {
    required String driverId,
    String? fleetOwnerId,
  }) async {
    final dao = DriverProfilesDao(txn);
    final existing = await dao.findByDriverId(driverId);
    final now = _nowUtc();
    await dao.upsert(
      DriverProfile(
        driverId: driverId,
        fleetOwnerId: fleetOwnerId ?? existing?.fleetOwnerId,
        cashDebtMinor: existing?.cashDebtMinor ?? 0,
        safetyScore: existing?.safetyScore ?? 0,
        status: existing?.status ?? 'active',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _upsertDriverBlockFlagTx(
    DatabaseExecutor txn,
    String driverId,
    bool blocked,
  ) async {
    final usersDao = UsersDao(txn);
    final existing = await usersDao.findById(driverId);
    final now = _nowUtc();
    if (existing == null) {
      await usersDao.insert(
        User(
          id: driverId,
          role: UserRole.driver,
          isBlocked: blocked,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    await usersDao.update(
      User(
        id: existing.id,
        role: existing.role,
        email: existing.email,
        displayName: existing.displayName,
        gender: existing.gender,
        tribe: existing.tribe,
        starRating: existing.starRating,
        luggageCount: existing.luggageCount,
        nextOfKinLocked: existing.nextOfKinLocked,
        crossBorderDocLocked: existing.crossBorderDocLocked,
        allowLocationOff: existing.allowLocationOff,
        isBlocked: blocked,
        disclosureAccepted: existing.disclosureAccepted,
        createdAt: existing.createdAt,
        updatedAt: now,
      ),
    );
  }

  Future<void> _upsertDriverCashDebtTx(
    DatabaseExecutor txn,
    String driverId,
    int cashDebtMinor,
  ) async {
    final dao = DriverProfilesDao(txn);
    final existing = await dao.findByDriverId(driverId);
    final now = _nowUtc();
    await dao.upsert(
      DriverProfile(
        driverId: driverId,
        fleetOwnerId: existing?.fleetOwnerId,
        cashDebtMinor: cashDebtMinor,
        safetyScore: existing?.safetyScore ?? 0,
        status: existing?.status ?? 'active',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  Future<String?> _driverFleetOwnerTx(
    DatabaseExecutor txn,
    String driverId,
  ) async {
    final profile = await DriverProfilesDao(txn).findByDriverId(driverId);
    final value = profile?.fleetOwnerId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<int> _fleetAllowancePercentTx(
    DatabaseExecutor txn,
    String fleetOwnerId,
  ) async {
    return FleetConfigsDao(txn).getAllowancePercent(fleetOwnerId);
  }

  Future<Wallet> _ensureWalletTx(
    DatabaseExecutor txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final repo = _walletRepositoryFor(txn);
    final existing = await repo.getWallet(ownerId, walletType);
    if (existing != null) {
      return existing;
    }
    final now = _nowUtc();
    final wallet = Wallet(
      ownerId: ownerId,
      walletType: walletType,
      balanceMinor: 0,
      reservedMinor: 0,
      currency: 'NGN',
      updatedAt: now,
      createdAt: now,
    );
    await repo.upsertWallet(wallet);
    return wallet;
  }

  Future<int> _walletBalanceTx(
    DatabaseExecutor txn, {
    required String ownerId,
    required WalletType walletType,
  }) async {
    final wallet = await _ensureWalletTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    return wallet.balanceMinor;
  }

  Future<int> _postWalletCreditTx(
    DatabaseExecutor txn, {
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

    final repo = _walletRepositoryFor(txn);
    final current = await _ensureWalletTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    final next = current.balanceMinor + amountMinor;
    final now = _nowUtc();

    await repo.upsertWallet(
      Wallet(
        ownerId: current.ownerId,
        walletType: current.walletType,
        balanceMinor: next,
        reservedMinor: current.reservedMinor,
        currency: current.currency,
        updatedAt: now,
        createdAt: current.createdAt,
      ),
    );

    await repo.appendLedger(
      WalletLedgerEntry(
        ownerId: ownerId,
        walletType: walletType,
        direction: LedgerDirection.credit,
        amountMinor: amountMinor,
        balanceAfterMinor: next,
        kind: kind,
        referenceId: referenceId,
        idempotencyScope: idempotencyScope,
        idempotencyKey: idempotencyKey,
        createdAt: now,
      ),
    );
    return next;
  }

  Future<int> _postWalletDebitTx(
    DatabaseExecutor txn, {
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
    final repo = _walletRepositoryFor(txn);
    final current = await _ensureWalletTx(
      txn,
      ownerId: ownerId,
      walletType: walletType,
    );
    if (current.balanceMinor < amountMinor) {
      throw StateError(
        'insufficient_funds_for_debit:$ownerId:${walletType.dbValue}',
      );
    }
    final next = current.balanceMinor - amountMinor;
    final now = _nowUtc();

    await repo.upsertWallet(
      Wallet(
        ownerId: current.ownerId,
        walletType: current.walletType,
        balanceMinor: next,
        reservedMinor: current.reservedMinor,
        currency: current.currency,
        updatedAt: now,
        createdAt: current.createdAt,
      ),
    );

    await repo.appendLedger(
      WalletLedgerEntry(
        ownerId: ownerId,
        walletType: walletType,
        direction: LedgerDirection.debit,
        amountMinor: amountMinor,
        balanceAfterMinor: next,
        kind: kind,
        referenceId: referenceId,
        idempotencyScope: idempotencyScope,
        idempotencyKey: idempotencyKey,
        createdAt: now,
      ),
    );
    return next;
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
    final result = await IdempotencyDao(txn).claim(scope: scope, key: key);
    return result.isNewClaim;
  }

  Future<String> _readIdempotencyHash(
    DatabaseExecutor txn, {
    required String scope,
    required String key,
  }) async {
    final record = await IdempotencyDao(txn).get(scope: scope, key: key);
    return record?.resultHash ?? '';
  }

  Future<void> _finalizeIdempotency(
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

  WalletRepository _walletRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteWalletRepository(
      walletsDao: WalletsDao(txnOrDb),
      walletLedgerDao: WalletLedgerDao(txnOrDb),
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
