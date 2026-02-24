import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hailo_shared/sqlite_api.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/wallet_ledger_dao.dart';
import '../../data/sqlite/dao/wallets_dao.dart';
import '../errors/domain_errors.dart';
import '../models/idempotency_record.dart';
import '../models/wallet.dart';
import '../models/wallet_ledger_entry.dart';
import 'finance_utils.dart';

class ReferralRewardService {
  ReferralRewardService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeFirstRideReward = 'referral.first_ride_reward';
  static const int _defaultRewardMinor = 500;

  Future<Map<String, Object?>> creditReferrerForFirstCompletedRide({
    required String riderUserId,
    required String rideId,
    required String idempotencyKey,
  }) async {
    final riderId = riderUserId.trim();
    final normalizedRideId = rideId.trim();
    final normalizedIdempotency = idempotencyKey.trim();
    if (riderId.isEmpty || normalizedRideId.isEmpty) {
      throw const DomainInvariantError(code: 'referral_reward_invalid_input');
    }
    if (normalizedIdempotency.isEmpty) {
      throw const DomainInvariantError(
        code: 'referral_reward_idempotency_required',
      );
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeFirstRideReward,
      key: normalizedIdempotency,
      requestHash: '$riderId|$normalizedRideId',
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': claim.record.status != IdempotencyStatus.failed,
        'replayed': true,
        'result_hash': claim.record.resultHash,
        'error': claim.record.errorCode,
      };
    }

    try {
      final result = await db.transaction((txn) async {
        final countRows = await txn.rawQuery(
          '''
          SELECT COUNT(*) AS c
          FROM rides
          WHERE rider_id = ?
            AND status IN ('completed','finance_settled')
          ''',
          <Object?>[riderId],
        );
        final completedCount = (countRows.first['c'] as num?)?.toInt() ?? 0;
        if (completedCount != 1) {
          return <String, Object?>{
            'ok': true,
            'credited': false,
            'reason': 'not_first_completed_ride',
            'completed_count': completedCount,
          };
        }

        final pendingRows = await txn.query(
          'promo_events',
          where: 'user_id = ? AND event_type = ? AND status = ?',
          whereArgs: <Object?>[riderId, 'referral_signup_pending', 'pending'],
          orderBy: 'created_at ASC',
          limit: 1,
        );
        if (pendingRows.isEmpty) {
          return const <String, Object?>{
            'ok': true,
            'credited': false,
            'reason': 'no_pending_referral_signup',
          };
        }

        final pending = pendingRows.first;
        final referrerUserId =
            (pending['related_user_id'] as String?)?.trim() ?? '';
        if (referrerUserId.isEmpty || referrerUserId == riderId) {
          return const <String, Object?>{
            'ok': true,
            'credited': false,
            'reason': 'invalid_referrer',
          };
        }

        final rewardMinor =
            ((pending['amount_minor'] as num?)?.toInt() ?? _defaultRewardMinor)
                .clamp(0, 1 << 30);
        if (rewardMinor <= 0) {
          return const <String, Object?>{
            'ok': true,
            'credited': false,
            'reason': 'reward_amount_zero',
          };
        }

        final now = _nowUtc();
        final nowIso = isoNowUtc(now);
        final walletsDao = WalletsDao(txn);
        final walletLedgerDao = WalletLedgerDao(txn);

        final existingWallet = await walletsDao.find(
          referrerUserId,
          WalletType.driverA,
        );
        final currentBalance = existingWallet?.balanceMinor ?? 0;
        final nextBalance = currentBalance + rewardMinor;

        await walletsDao.upsert(
          Wallet(
            ownerId: referrerUserId,
            walletType: WalletType.driverA,
            balanceMinor: nextBalance,
            reservedMinor: existingWallet?.reservedMinor ?? 0,
            currency: existingWallet?.currency ?? 'NGN',
            updatedAt: now,
            createdAt: existingWallet?.createdAt ?? now,
          ),
          viaOrchestrator: true,
        );
        await walletLedgerDao.append(
          WalletLedgerEntry(
            ownerId: referrerUserId,
            walletType: WalletType.driverA,
            direction: LedgerDirection.credit,
            amountMinor: rewardMinor,
            balanceAfterMinor: nextBalance,
            kind: 'referral_first_ride_reward',
            referenceId: normalizedRideId,
            idempotencyScope: _scopeFirstRideReward,
            idempotencyKey: normalizedIdempotency,
            createdAt: now,
          ),
          viaOrchestrator: true,
        );

        await txn.update(
          'promo_events',
          <String, Object?>{
            'status': 'credited',
            'idempotency_scope': _scopeFirstRideReward,
            'idempotency_key': normalizedIdempotency,
          },
          where: 'id = ?',
          whereArgs: <Object?>[pending['id']],
        );
        await txn.insert('promo_events', <String, Object?>{
          'id': 'promo_referrer_reward:$normalizedRideId',
          'event_type': 'referrer_reward_credited',
          'user_id': referrerUserId,
          'related_user_id': riderId,
          'amount_minor': rewardMinor,
          'status': 'credited',
          'created_at': nowIso,
          'idempotency_scope': _scopeFirstRideReward,
          'idempotency_key': '$normalizedIdempotency:referrer_event',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        return <String, Object?>{
          'ok': true,
          'credited': true,
          'referrer_user_id': referrerUserId,
          'reward_minor': rewardMinor,
          'wallet_balance_after_minor': nextBalance,
        };
      });

      final resultHash = _hash(result);
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeFirstRideReward,
        key: normalizedIdempotency,
        resultHash: resultHash,
      );
      return <String, Object?>{...result, 'result_hash': resultHash};
    } catch (_) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeFirstRideReward,
        key: normalizedIdempotency,
        errorCode: 'referral_reward_exception',
      );
      rethrow;
    }
  }

  String _hash(Map<String, Object?> value) {
    return sha256.convert(utf8.encode(jsonEncode(value))).toString();
  }
}
