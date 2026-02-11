import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/repositories/sqlite_wallet_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/penalties_dao.dart';
import '../../data/sqlite/dao/penalty_records_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../../data/sqlite/dao/wallet_ledger_dao.dart';
import '../../data/sqlite/dao/wallets_dao.dart';
import '../models/idempotency_record.dart';
import '../models/penalty_audit_record.dart';
import '../models/penalty_record.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';
import 'finance_utils.dart';
import 'penalty_engine_service.dart';

class CancellationResult {
  const CancellationResult({
    required this.ok,
    required this.rideId,
    required this.penaltyMinor,
    required this.status,
    required this.replayed,
    this.ruleCode,
    this.resultHash,
    this.error,
  });

  final bool ok;
  final String rideId;
  final int penaltyMinor;
  final String status;
  final bool replayed;
  final String? ruleCode;
  final String? resultHash;
  final String? error;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ok': ok,
      'ride_id': rideId,
      'penalty_minor': penaltyMinor,
      'status': status,
      'replayed': replayed,
      'rule_code': ruleCode,
      'result_hash': resultHash,
      'error': error,
    };
  }
}

class CancelRideService {
  CancelRideService(
    this.db, {
    PenaltyEngineService? penaltyEngineService,
    DateTime Function()? nowUtc,
  }) : _penaltyEngineService =
           penaltyEngineService ?? const PenaltyEngineService(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final PenaltyEngineService _penaltyEngineService;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeCancellationPenalty = 'cancellation_penalty';
  static const String _platformOwnerId = 'platform';

  /// Legacy convenience wrapper.
  ///
  /// New code should call [collectCancellationPenalty] directly after it has
  /// already computed/selected the penalty amount and rule code.
  Future<CancellationResult> cancelRideAndCollectPenalty({
    required String rideId,
    required String payerUserId,
    required RideType rideType,
    required int totalFareMinor,
    required DateTime scheduledDeparture,
    required DateTime cancelledAt,
    required String idempotencyKey,
  }) async {
    final computation = _penaltyEngineService.computeCancellationPenaltyMinor(
      rideType: rideType,
      totalFareMinor: totalFareMinor,
      scheduledDeparture: scheduledDeparture,
      cancelledAt: cancelledAt,
    );

    return collectCancellationPenalty(
      rideId: rideId,
      payerUserId: payerUserId,
      penaltyMinor: computation.penaltyMinor,
      idempotencyKey: idempotencyKey,
      ruleCode: computation.ruleCode,
      rideType: rideType.dbValue,
      totalFareMinor: totalFareMinor,
      cancelledAt: cancelledAt,
    );
  }

  /// Canonical public cancellation entrypoint.
  ///
  /// This method enforces idempotency and guarantees cancellation money
  /// mutations are ledger-backed before ride status transitions to cancelled.
  Future<CancellationResult> collectCancellationPenalty({
    required String rideId,
    required String payerUserId,
    required int penaltyMinor,
    required String idempotencyKey,
    String ruleCode = 'cancellation_penalty_assessed',
    String? rideType,
    int? totalFareMinor,
    DateTime? cancelledAt,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }
    if (penaltyMinor < 0) {
      throw ArgumentError('penaltyMinor must be >= 0');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeCancellationPenalty,
      key: idempotencyKey,
      requestHash: '$rideId|$payerUserId|$penaltyMinor|$ruleCode',
    );

    if (!claim.isNewClaim) {
      final existing = await PenaltyRecordsDao(db).findByIdempotency(
        idempotencyScope: _scopeCancellationPenalty,
        idempotencyKey: idempotencyKey,
      );
      if (claim.record.status == IdempotencyStatus.success &&
          existing != null) {
        return CancellationResult(
          ok: true,
          rideId: rideId,
          penaltyMinor: existing.amountMinor,
          status: existing.status,
          replayed: true,
          ruleCode: existing.ruleCode,
          resultHash: claim.record.resultHash,
        );
      }
      return CancellationResult(
        ok: false,
        rideId: rideId,
        penaltyMinor: 0,
        status: 'failed',
        replayed: true,
        error: claim.record.errorCode ?? 'previous_attempt_failed',
      );
    }

    try {
      final result = await db.transaction((txn) async {
        final now = cancelledAt?.toUtc() ?? _nowUtc();
        final nowIso = isoNowUtc(now);

        // Compatibility mirror: legacy consumers still read `penalties`.
        // Canonical audit/idempotency is persisted in `penalty_records`.
        await PenaltiesDao(txn).insert(
          PenaltyRecord(
            id: 'penalty:$rideId',
            userId: payerUserId,
            penaltyKind: ruleCode,
            amountMinor: penaltyMinor,
            reason: rideId,
            createdAt: now,
            idempotencyScope: _scopeCancellationPenalty,
            idempotencyKey: idempotencyKey,
          ),
        );

        var status = 'assessed';
        if (penaltyMinor > 0) {
          await _transferPenalty(
            txn,
            rideId: rideId,
            payerUserId: payerUserId,
            penaltyMinor: penaltyMinor,
            idempotencyKey: idempotencyKey,
          );
          status = 'collected';
        }

        await PenaltyRecordsDao(txn).insert(
          PenaltyAuditRecord(
            id: 'penalty_record:$rideId',
            rideId: rideId,
            userId: payerUserId,
            amountMinor: penaltyMinor,
            ruleCode: ruleCode,
            status: status,
            idempotencyScope: _scopeCancellationPenalty,
            idempotencyKey: idempotencyKey,
            createdAt: now,
            rideType: rideType,
            totalFareMinor: totalFareMinor,
            collectedToOwnerId: penaltyMinor > 0 ? _platformOwnerId : null,
            collectedToWalletType: penaltyMinor > 0
                ? WalletType.platform.dbValue
                : null,
          ),
        );
        await RidesDao(txn).markCancelled(
          rideId: rideId,
          nowIso: nowIso,
          viaCancelRideService: true,
        );

        return CancellationResult(
          ok: true,
          rideId: rideId,
          penaltyMinor: penaltyMinor,
          status: status,
          replayed: false,
          ruleCode: ruleCode,
        );
      });

      final hash = sha256
          .convert(utf8.encode(jsonEncode(result.toMap())))
          .toString();
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeCancellationPenalty,
        key: idempotencyKey,
        resultHash: hash,
      );
      return CancellationResult(
        ok: result.ok,
        rideId: result.rideId,
        penaltyMinor: result.penaltyMinor,
        status: result.status,
        replayed: result.replayed,
        ruleCode: result.ruleCode,
        resultHash: hash,
      );
    } catch (_) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeCancellationPenalty,
        key: idempotencyKey,
        errorCode: 'cancellation_penalty_exception',
      );
      rethrow;
    }
  }

  Future<void> _transferPenalty(
    DatabaseExecutor txn, {
    required String rideId,
    required String payerUserId,
    required int penaltyMinor,
    required String idempotencyKey,
  }) async {
    final repo = _walletRepositoryFor(txn);
    final now = _nowUtc();

    final payerWallet = await _ensureWallet(
      txn,
      ownerId: payerUserId,
      walletType: WalletType.driverA,
    );
    if (payerWallet.balanceMinor < penaltyMinor) {
      throw StateError('insufficient_payer_balance');
    }

    final payerNext = payerWallet.balanceMinor - penaltyMinor;
    await repo.upsertWallet(
      Wallet(
        ownerId: payerWallet.ownerId,
        walletType: payerWallet.walletType,
        balanceMinor: payerNext,
        reservedMinor: payerWallet.reservedMinor,
        currency: payerWallet.currency,
        updatedAt: now,
        createdAt: payerWallet.createdAt,
      ),
    );
    await repo.appendLedger(
      WalletLedgerEntry(
        ownerId: payerUserId,
        walletType: WalletType.driverA,
        direction: LedgerDirection.debit,
        amountMinor: penaltyMinor,
        balanceAfterMinor: payerNext,
        kind: 'cancellation_penalty_debit',
        referenceId: rideId,
        idempotencyScope: _scopeCancellationPenalty,
        idempotencyKey: '$idempotencyKey:payer_debit',
        createdAt: now,
      ),
    );

    final platformWallet = await _ensureWallet(
      txn,
      ownerId: _platformOwnerId,
      walletType: WalletType.platform,
    );
    final platformNext = platformWallet.balanceMinor + penaltyMinor;
    await repo.upsertWallet(
      Wallet(
        ownerId: platformWallet.ownerId,
        walletType: platformWallet.walletType,
        balanceMinor: platformNext,
        reservedMinor: platformWallet.reservedMinor,
        currency: platformWallet.currency,
        updatedAt: now,
        createdAt: platformWallet.createdAt,
      ),
    );
    await repo.appendLedger(
      WalletLedgerEntry(
        ownerId: _platformOwnerId,
        walletType: WalletType.platform,
        direction: LedgerDirection.credit,
        amountMinor: penaltyMinor,
        balanceAfterMinor: platformNext,
        kind: 'cancellation_penalty_credit',
        referenceId: rideId,
        idempotencyScope: _scopeCancellationPenalty,
        idempotencyKey: '$idempotencyKey:platform_credit',
        createdAt: now,
      ),
    );
  }

  Future<Wallet> _ensureWallet(
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

  WalletRepository _walletRepositoryFor(DatabaseExecutor txnOrDb) {
    return SqliteWalletRepository(
      walletsDao: WalletsDao(txnOrDb),
      walletLedgerDao: WalletLedgerDao(txnOrDb),
    );
  }
}
