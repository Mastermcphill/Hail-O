import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/dispute_events_dao.dart';
import '../../data/sqlite/dao/disputes_dao.dart';
import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/payout_records_dao.dart';
import '../../data/sqlite/dao/wallet_ledger_dao.dart';
import '../../data/sqlite/dao/wallets_dao.dart';
import '../errors/domain_errors.dart';
import '../models/dispute.dart';
import '../models/dispute_event.dart';
import '../models/idempotency_record.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';
import 'finance_utils.dart';
import 'wallet_reversal_service.dart';

class DisputeService {
  DisputeService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db),
      _walletReversalService = WalletReversalService(db, nowUtc: nowUtc);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;
  final WalletReversalService _walletReversalService;

  static const String _scopeDisputeOpen = 'dispute.open';
  static const String _scopeDisputeResolve = 'dispute.resolve';

  Future<Map<String, Object?>> openDispute({
    required String disputeId,
    required String rideId,
    required String openedBy,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeDisputeOpen,
      key: idempotencyKey,
      requestHash: '$disputeId|$rideId|$openedBy|$reason',
    );
    if (!claim.isNewClaim) {
      return _buildReplayResponse(claim.record);
    }

    try {
      final now = _nowUtc();
      final result = await db.transaction((txn) async {
        final disputesDao = DisputesDao(txn);
        final existing = await disputesDao.findById(disputeId);
        if (existing != null) {
          return <String, Object?>{
            'ok': true,
            'replayed': true,
            'dispute_id': existing.id,
            'status': existing.status,
            'ride_id': existing.rideId,
          };
        }

        final dispute = DisputeRecord(
          id: disputeId,
          rideId: rideId,
          openedBy: openedBy,
          status: 'open',
          reason: reason,
          createdAt: now,
        );
        await disputesDao.insert(dispute, viaOrchestrator: true);
        await DisputeEventsDao(txn).insert(
          DisputeEventRecord(
            id: '$disputeId:opened',
            disputeId: disputeId,
            eventType: 'opened',
            actorId: openedBy,
            payloadJson: jsonEncode(<String, Object?>{'reason': reason}),
            idempotencyScope: _scopeDisputeOpen,
            idempotencyKey: idempotencyKey,
            createdAt: now,
          ),
          viaOrchestrator: true,
        );
        return <String, Object?>{
          'ok': true,
          'replayed': false,
          'dispute_id': disputeId,
          'status': 'open',
          'ride_id': rideId,
        };
      });

      await _idempotencyStore.finalizeSuccess(
        scope: _scopeDisputeOpen,
        key: idempotencyKey,
        resultHash: _hashResult(result),
      );
      return result;
    } catch (e) {
      final code = e is DomainError ? e.code : 'dispute_open_exception';
      await _idempotencyStore.finalizeFailure(
        scope: _scopeDisputeOpen,
        key: idempotencyKey,
        errorCode: code,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> resolveDispute({
    required String disputeId,
    required String resolverUserId,
    required bool resolverIsAdmin,
    required int refundMinor,
    required String idempotencyKey,
    String resolutionNote = 'resolved',
  }) async {
    if (!resolverIsAdmin) {
      throw const UnauthorizedActionError(code: 'dispute_resolve_forbidden');
    }
    if (refundMinor < 0) {
      throw ArgumentError('refundMinor must be >= 0');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeDisputeResolve,
      key: idempotencyKey,
      requestHash: '$disputeId|$resolverUserId|$refundMinor',
    );
    if (!claim.isNewClaim) {
      return _buildReplayResponse(claim.record);
    }

    try {
      final now = _nowUtc();
      final disputesDao = DisputesDao(db);
      final dispute = await disputesDao.findById(disputeId);
      if (dispute == null) {
        throw const DomainInvariantError(code: 'dispute_not_found');
      }
      if (dispute.status != 'open') {
        final replay = <String, Object?>{
          'ok': true,
          'replayed': true,
          'dispute_id': dispute.id,
          'status': dispute.status,
          'refund_minor': dispute.refundMinorTotal,
        };
        await _idempotencyStore.finalizeSuccess(
          scope: _scopeDisputeResolve,
          key: idempotencyKey,
          resultHash: _hashResult(replay),
        );
        return replay;
      }

      final payout = await PayoutRecordsDao(
        db,
      ).findLatestByRideId(dispute.rideId);
      if (payout == null) {
        throw const DomainInvariantError(code: 'payout_not_found_for_dispute');
      }
      final alreadyRefunded = await _alreadyRefundedForRide(dispute.rideId);
      final maxRefundable = payout.totalPaidMinor - alreadyRefunded;
      if (refundMinor > maxRefundable) {
        throw DomainInvariantError(
          code: 'refund_exceeds_paid',
          metadata: <String, Object?>{
            'max_refundable_minor': maxRefundable,
            'requested_refund_minor': refundMinor,
          },
        );
      }

      int? originalLedgerId;
      int? reversalLedgerId;
      if (refundMinor > 0) {
        final sourceLedger = await _findRefundSourceLedger(
          rideId: dispute.rideId,
          ownerId: payout.recipientOwnerId,
        );
        if (sourceLedger == null) {
          throw const DomainInvariantError(
            code: 'refund_source_ledger_not_found',
          );
        }
        originalLedgerId = sourceLedger.id;
        final reversal = await _walletReversalService.reverseWalletLedgerEntry(
          originalLedgerId: sourceLedger.id!,
          requestedByUserId: resolverUserId,
          requesterIsAdmin: true,
          reason: 'dispute_refund:$disputeId',
          idempotencyKey: '$idempotencyKey:reversal',
          reversalAmountMinor: refundMinor,
        );
        if (reversal['ok'] != true) {
          throw DomainInvariantError(
            code: 'dispute_reversal_failed',
            metadata: <String, Object?>{'reversal': reversal},
          );
        }
        reversalLedgerId = (reversal['reversal_ledger_id'] as num?)?.toInt();
      }

      final result = await db.transaction((txn) async {
        if (refundMinor > 0) {
          final riderWalletBalance = await _creditWallet(
            txn,
            ownerId: dispute.openedBy,
            walletType: WalletType.driverA,
            amountMinor: refundMinor,
            kind: 'dispute_refund_credit',
            referenceId: dispute.rideId,
            idempotencyScope: _scopeDisputeResolve,
            idempotencyKey: '$idempotencyKey:rider_credit',
            createdAt: now,
          );
          await DisputeEventsDao(txn).insert(
            DisputeEventRecord(
              id: '$disputeId:refund_applied',
              disputeId: disputeId,
              eventType: 'refund_applied',
              actorId: resolverUserId,
              payloadJson: jsonEncode(<String, Object?>{
                'refund_minor': refundMinor,
                'ride_id': dispute.rideId,
                'original_ledger_id': originalLedgerId,
                'reversal_ledger_id': reversalLedgerId,
                'rider_wallet_balance_after_minor': riderWalletBalance,
              }),
              idempotencyScope: _scopeDisputeResolve,
              idempotencyKey: '$idempotencyKey:refund_event',
              createdAt: now,
            ),
            viaOrchestrator: true,
          );
        }

        final resolved = DisputeRecord(
          id: dispute.id,
          rideId: dispute.rideId,
          openedBy: dispute.openedBy,
          status: 'resolved',
          reason: dispute.reason,
          createdAt: dispute.createdAt,
          resolvedAt: now,
          resolverUserId: resolverUserId,
          resolutionNote: resolutionNote,
          refundMinorTotal: dispute.refundMinorTotal + refundMinor,
        );
        await DisputesDao(txn).update(resolved, viaOrchestrator: true);
        await DisputeEventsDao(txn).insert(
          DisputeEventRecord(
            id: '$disputeId:resolved',
            disputeId: disputeId,
            eventType: 'resolved',
            actorId: resolverUserId,
            payloadJson: jsonEncode(<String, Object?>{
              'refund_minor': refundMinor,
              'resolution_note': resolutionNote,
              'original_ledger_id': originalLedgerId,
              'reversal_ledger_id': reversalLedgerId,
            }),
            idempotencyScope: _scopeDisputeResolve,
            idempotencyKey: '$idempotencyKey:resolve_event',
            createdAt: now,
          ),
          viaOrchestrator: true,
        );

        return <String, Object?>{
          'ok': true,
          'replayed': false,
          'dispute_id': disputeId,
          'status': 'resolved',
          'refund_minor': refundMinor,
          'max_refundable_minor': maxRefundable,
          'original_ledger_id': originalLedgerId,
          'reversal_ledger_id': reversalLedgerId,
        };
      });

      await _idempotencyStore.finalizeSuccess(
        scope: _scopeDisputeResolve,
        key: idempotencyKey,
        resultHash: _hashResult(result),
      );
      return result;
    } catch (e) {
      final code = e is DomainError ? e.code : 'dispute_resolve_exception';
      await _idempotencyStore.finalizeFailure(
        scope: _scopeDisputeResolve,
        key: idempotencyKey,
        errorCode: code,
      );
      rethrow;
    }
  }

  Future<int> _alreadyRefundedForRide(String rideId) async {
    final disputes = await DisputesDao(db).listByRideId(rideId);
    var total = 0;
    for (final dispute in disputes) {
      total += dispute.refundMinorTotal;
    }
    return total;
  }

  Future<WalletLedgerEntry?> _findRefundSourceLedger({
    required String rideId,
    required String ownerId,
  }) async {
    final entries = await WalletLedgerDao(db).listCreditsByReference(rideId);
    for (final entry in entries) {
      if (entry.ownerId == ownerId && entry.amountMinor > 0) {
        return entry;
      }
    }
    return null;
  }

  Future<int> _creditWallet(
    DatabaseExecutor txn, {
    required String ownerId,
    required WalletType walletType,
    required int amountMinor,
    required String kind,
    required String referenceId,
    required String idempotencyScope,
    required String idempotencyKey,
    required DateTime createdAt,
  }) async {
    final walletsDao = WalletsDao(txn);
    final walletLedgerDao = WalletLedgerDao(txn);
    final nowIso = isoNowUtc(createdAt);
    var wallet = await walletsDao.find(ownerId, walletType);
    if (wallet == null) {
      wallet = Wallet(
        ownerId: ownerId,
        walletType: walletType,
        balanceMinor: 0,
        reservedMinor: 0,
        currency: 'NGN',
        updatedAt: createdAt,
        createdAt: createdAt,
      );
      await walletsDao.upsert(wallet, viaOrchestrator: true);
    }

    final next = wallet.balanceMinor + amountMinor;
    await walletsDao.upsert(
      Wallet(
        ownerId: wallet.ownerId,
        walletType: wallet.walletType,
        balanceMinor: next,
        reservedMinor: wallet.reservedMinor,
        currency: wallet.currency,
        updatedAt: DateTime.parse(nowIso).toUtc(),
        createdAt: wallet.createdAt,
      ),
      viaOrchestrator: true,
    );
    await walletLedgerDao.append(
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
        createdAt: createdAt,
      ),
      viaOrchestrator: true,
    );
    return next;
  }

  Map<String, Object?> _buildReplayResponse(IdempotencyRecord record) {
    return <String, Object?>{
      'ok': record.status == IdempotencyStatus.success,
      'replayed': true,
      'result_hash': record.resultHash,
      'error': record.errorCode,
    };
  }

  String _hashResult(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }
}
