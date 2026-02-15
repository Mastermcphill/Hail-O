import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/repositories/sqlite_wallet_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/sqlite/dao/driver_profiles_dao.dart';
import '../../data/sqlite/dao/escrow_holds_dao.dart';
import '../../data/sqlite/dao/fleet_configs_dao.dart';
import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/penalties_dao.dart';
import '../../data/sqlite/dao/penalty_records_dao.dart';
import '../../data/sqlite/dao/payout_records_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../../data/sqlite/dao/seats_dao.dart';
import '../../data/sqlite/dao/wallet_ledger_dao.dart';
import '../../data/sqlite/dao/wallets_dao.dart';
import '../models/idempotency_record.dart';
import '../models/payout_record.dart';
import '../models/settlement_result.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';
import 'ride_lifecycle_guard_service.dart';
import '../../services/autosave_service.dart';
import '../../services/moneybox_service.dart';
import 'finance_utils.dart';

export '../models/settlement_result.dart'
    show SettlementResult, SettlementTrigger;

class RideSettlementService {
  RideSettlementService(
    this.db, {
    AutosaveService? autosaveService,
    DateTime Function()? nowUtc,
  }) : _autosaveService =
           autosaveService ??
           AutosaveService(
             db,
             moneyBoxService: MoneyBoxService(db, nowUtc: nowUtc),
             nowUtc: nowUtc,
           ),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final AutosaveService _autosaveService;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeSettleOnEscrowRelease = 'ride_settlement';
  static const RideLifecycleGuardService _rideLifecycleGuard =
      RideLifecycleGuardService();

  Future<SettlementResult> settleOnEscrowRelease({
    required String escrowId,
    required String rideId,
    required String idempotencyKey,
    required SettlementTrigger trigger,
  }) async {
    _requireIdempotency(idempotencyKey);
    final canonicalIdempotencyKey = _canonicalIdempotencyKey(escrowId);

    final claim = await _idempotencyStore.claim(
      scope: _scopeSettleOnEscrowRelease,
      key: canonicalIdempotencyKey,
      requestHash: '$escrowId|$rideId|${trigger.dbValue}',
    );

    if (!claim.isNewClaim) {
      return _buildReplayResult(
        record: claim.record,
        rideId: rideId,
        escrowId: escrowId,
      );
    }

    try {
      final result = await db.transaction((txn) async {
        final payoutDao = PayoutRecordsDao(txn);
        final existingPayout = await payoutDao.findByEscrowId(escrowId);
        if (existingPayout != null) {
          return _settlementFromPayout(existingPayout, replayed: true);
        }

        final escrow = await EscrowHoldsDao(txn).findById(escrowId);
        if (escrow == null) {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: 'escrow_not_found',
          );
        }
        if (escrow.status != 'released') {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: 'escrow_not_released',
          );
        }
        if (escrow.rideId != rideId) {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: 'ride_escrow_mismatch',
          );
        }

        final ride = await RidesDao(txn).findById(rideId);
        if (ride == null) {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: 'ride_not_found',
          );
        }

        final driverId = (ride['driver_id'] as String?)?.trim() ?? '';
        if (driverId.isEmpty) {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: 'ride_missing_driver',
          );
        }

        final rideStatus = (ride['status'] as String?) ?? '';
        try {
          _rideLifecycleGuard.assertCanSettleFinance(rideStatus);
        } on RideLifecycleViolation catch (e) {
          return SettlementResult.error(
            rideId: rideId,
            escrowId: escrowId,
            error: e.code,
          );
        }

        final baseFareMinor = (ride['base_fare_minor'] as int?) ?? 0;
        final ridePremiumMarkupMinor =
            (ride['premium_markup_minor'] as int?) ?? 0;
        final seatPremiumMarkupMinor = await SeatsDao(
          txn,
        ).sumMarkupMinorByRide(rideId);
        final premiumMarkupMinor = seatPremiumMarkupMinor > 0
            ? seatPremiumMarkupMinor
            : ridePremiumMarkupMinor;

        var penaltyDueMinor = 0;
        final penaltyAuditRows = await PenaltyRecordsDao(
          txn,
        ).listByRideId(rideId);
        if (penaltyAuditRows.isNotEmpty) {
          for (final penalty in penaltyAuditRows) {
            penaltyDueMinor += penalty.amountMinor;
          }
        } else {
          final penalties = await PenaltiesDao(
            txn,
          ).listByUserAndReason(userId: driverId, reason: rideId);
          for (final penalty in penalties) {
            penaltyDueMinor += penalty.amountMinor;
          }
        }

        final profile = await DriverProfilesDao(txn).findByDriverId(driverId);
        final fleetOwnerRaw = profile?.fleetOwnerId?.trim();
        final fleetOwnerId = (fleetOwnerRaw == null || fleetOwnerRaw.isEmpty)
            ? null
            : fleetOwnerRaw;
        final hasFleetOwner = fleetOwnerId != null;
        final allowancePercent = hasFleetOwner
            ? await FleetConfigsDao(txn).getAllowancePercent(fleetOwnerId)
            : 0;

        final commissionGrossMinor = percentOf(baseFareMinor, 80);
        final premiumLockedMinor = percentOf(premiumMarkupMinor, 50);
        final recipientOwnerId = fleetOwnerId ?? driverId;
        final recipientWalletType = hasFleetOwner
            ? WalletType.fleetOwner
            : WalletType.driverA;

        var commissionSavedMinor = 0;
        var commissionRemainderMinor = commissionGrossMinor;
        if (commissionGrossMinor > 0) {
          final autosaveResult = await _autosaveService
              .applyOnConfirmedCommissionCreditWithExecutor(
                executor: txn,
                ownerId: recipientOwnerId,
                destinationWalletType: recipientWalletType,
                grossAmountMinor: commissionGrossMinor,
                sourceKind: AutosaveService.confirmedCommissionCredit,
                referenceId: rideId,
                idempotencyKey: '$idempotencyKey:commission_credit',
              );

          if (autosaveResult['ok'] != true) {
            return SettlementResult.error(
              rideId: rideId,
              escrowId: escrowId,
              error: 'autosave_split_failed',
            );
          }

          commissionSavedMinor =
              (autosaveResult['saved_minor'] as num?)?.toInt() ?? 0;
          commissionRemainderMinor =
              (autosaveResult['remainder_minor'] as num?)?.toInt() ??
              commissionGrossMinor;
        }

        final driverAllowanceMinor = hasFleetOwner && commissionGrossMinor > 0
            ? percentOf(commissionGrossMinor, allowancePercent)
            : 0;
        if (driverAllowanceMinor > 0) {
          await _postWalletCreditTx(
            txn,
            ownerId: driverId,
            walletType: WalletType.driverA,
            amountMinor: driverAllowanceMinor,
            kind: 'fleet_driver_allowance',
            referenceId: rideId,
            idempotencyScope: _scopeSettleOnEscrowRelease,
            idempotencyKey: '$idempotencyKey:driver_allowance',
          );
        }

        if (premiumLockedMinor > 0) {
          await _postWalletCreditTx(
            txn,
            ownerId: driverId,
            walletType: WalletType.driverB,
            amountMinor: premiumLockedMinor,
            kind: 'premium_markup_50_locked',
            referenceId: rideId,
            idempotencyScope: _scopeSettleOnEscrowRelease,
            idempotencyKey: '$idempotencyKey:premium_wallet_b',
          );
        }

        final cashDebtMinor = 0;
        final totalPaidMinor =
            commissionRemainderMinor +
            premiumLockedMinor +
            driverAllowanceMinor;
        final now = _nowUtc();

        await payoutDao.insert(
          PayoutRecord(
            id: 'payout:$escrowId',
            rideId: rideId,
            escrowId: escrowId,
            trigger: trigger.dbValue,
            status: 'completed',
            recipientOwnerId: recipientOwnerId,
            recipientWalletType: recipientWalletType.dbValue,
            totalPaidMinor: totalPaidMinor,
            commissionGrossMinor: commissionGrossMinor,
            commissionSavedMinor: commissionSavedMinor,
            commissionRemainderMinor: commissionRemainderMinor,
            premiumLockedMinor: premiumLockedMinor,
            driverAllowanceMinor: driverAllowanceMinor,
            cashDebtMinor: cashDebtMinor,
            penaltyDueMinor: penaltyDueMinor,
            breakdownJson: jsonEncode(<String, Object?>{
              'commission_gross_minor': commissionGrossMinor,
              'commission_saved_minor': commissionSavedMinor,
              'commission_remainder_minor': commissionRemainderMinor,
              'premium_locked_minor': premiumLockedMinor,
              'driver_allowance_minor': driverAllowanceMinor,
              'penalty_due_minor': penaltyDueMinor,
              'penalty_source': penaltyAuditRows.isNotEmpty
                  ? 'penalty_records'
                  : 'penalties_legacy',
            }),
            idempotencyScope: _scopeSettleOnEscrowRelease,
            idempotencyKey: canonicalIdempotencyKey,
            createdAt: now,
          ),
          viaOrchestrator: true,
        );

        await RidesDao(txn).updateFinanceIfExists(
          rideId: rideId,
          baseFareMinor: baseFareMinor,
          premiumSeatMarkupMinor: premiumMarkupMinor,
          nowIso: isoNowUtc(now),
          viaFinanceSettlementService: true,
        );

        return SettlementResult(
          ok: true,
          rideId: rideId,
          escrowId: escrowId,
          trigger: trigger,
          recipientOwnerId: recipientOwnerId,
          recipientWalletType: recipientWalletType,
          totalPaidMinor: totalPaidMinor,
          commissionGrossMinor: commissionGrossMinor,
          commissionSavedMinor: commissionSavedMinor,
          commissionRemainderMinor: commissionRemainderMinor,
          premiumLockedMinor: premiumLockedMinor,
          driverAllowanceMinor: driverAllowanceMinor,
          cashDebtMinor: cashDebtMinor,
          penaltyDueMinor: penaltyDueMinor,
        );
      });

      if (!result.ok) {
        await _idempotencyStore.finalizeFailure(
          scope: _scopeSettleOnEscrowRelease,
          key: canonicalIdempotencyKey,
          errorCode: result.error ?? 'ride_settlement_failed',
        );
        return result;
      }

      final hash = _hashResult(result);
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeSettleOnEscrowRelease,
        key: canonicalIdempotencyKey,
        resultHash: hash,
      );
      return result.copyWith(resultHash: hash);
    } catch (_) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeSettleOnEscrowRelease,
        key: canonicalIdempotencyKey,
        errorCode: 'ride_settlement_exception',
      );
      rethrow;
    }
  }

  Future<SettlementResult> _buildReplayResult({
    required IdempotencyRecord record,
    required String rideId,
    required String escrowId,
  }) async {
    if (record.status == IdempotencyStatus.success) {
      final payout =
          await PayoutRecordsDao(db).findByEscrowId(escrowId) ??
          await PayoutRecordsDao(db).findByIdempotency(
            idempotencyScope: _scopeSettleOnEscrowRelease,
            idempotencyKey: record.key,
          );
      if (payout != null) {
        return _settlementFromPayout(
          payout,
          replayed: true,
          resultHash: record.resultHash,
        );
      }
      return SettlementResult.error(
        rideId: rideId,
        escrowId: escrowId,
        error: 'replayed_without_payout_record',
        resultHash: record.resultHash,
        replayed: true,
      );
    }

    return SettlementResult.error(
      rideId: rideId,
      escrowId: escrowId,
      error: record.errorCode ?? 'ride_settlement_failed',
      resultHash: record.resultHash,
      replayed: true,
    );
  }

  SettlementResult _settlementFromPayout(
    PayoutRecord payout, {
    required bool replayed,
    String? resultHash,
  }) {
    return SettlementResult(
      ok: true,
      rideId: payout.rideId,
      escrowId: payout.escrowId,
      trigger: SettlementTrigger.fromDbValue(payout.trigger),
      recipientOwnerId: payout.recipientOwnerId,
      recipientWalletType: WalletType.fromDbValue(payout.recipientWalletType),
      totalPaidMinor: payout.totalPaidMinor,
      commissionGrossMinor: payout.commissionGrossMinor,
      commissionSavedMinor: payout.commissionSavedMinor,
      commissionRemainderMinor: payout.commissionRemainderMinor,
      premiumLockedMinor: payout.premiumLockedMinor,
      driverAllowanceMinor: payout.driverAllowanceMinor,
      cashDebtMinor: payout.cashDebtMinor,
      penaltyDueMinor: payout.penaltyDueMinor,
      replayed: replayed,
      resultHash: resultHash,
    );
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
      final wallet = await _ensureWalletTx(
        txn,
        ownerId: ownerId,
        walletType: walletType,
      );
      return wallet.balanceMinor;
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

  WalletRepository _walletRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteWalletRepository(
      walletsDao: WalletsDao(txnOrDb),
      walletLedgerDao: WalletLedgerDao(txnOrDb),
    );
  }

  String _hashResult(SettlementResult result) {
    return sha256.convert(utf8.encode(jsonEncode(result.toMap()))).toString();
  }

  String _canonicalIdempotencyKey(String escrowId) => 'settlement:$escrowId';

  void _requireIdempotency(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
  }
}
