import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';

class BreakdownSettlement {
  const BreakdownSettlement({
    required this.farePerKm,
    required this.payableMinor,
    required this.oldDriverCreditMinor,
    required this.remainingFareMinor,
    required this.rescueOfferMinor,
  });

  final double farePerKm;
  final int payableMinor;
  final int oldDriverCreditMinor;
  final int remainingFareMinor;
  final int rescueOfferMinor;
}

typedef RescueBroadcast =
    Future<void> Function({
      required String rideId,
      required int rescueOfferMinor,
    });

class BreakdownRecoveryService {
  BreakdownRecoveryService(
    this.db, {
    RescueBroadcast? onBroadcast,
    DateTime Function()? nowUtc,
  }) : _onBroadcast = onBroadcast ?? _defaultBroadcast,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final RescueBroadcast _onBroadcast;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeBreakdown = 'trip.breakdown.recovery';

  BreakdownSettlement computeBreakdownSettlement({
    required int totalFareMinor,
    required double totalDistKm,
    required double coveredDistKm,
  }) {
    if (totalFareMinor <= 0 || totalDistKm <= 0 || coveredDistKm <= 0) {
      return const BreakdownSettlement(
        farePerKm: 0,
        payableMinor: 0,
        oldDriverCreditMinor: 0,
        remainingFareMinor: 0,
        rescueOfferMinor: 0,
      );
    }

    final cappedCovered = coveredDistKm > totalDistKm
        ? totalDistKm
        : coveredDistKm;
    final farePerKm = totalFareMinor / totalDistKm;
    final payable = (farePerKm * cappedCovered).round();
    final oldDriverCredit = payable - ((payable * 20) ~/ 100);
    final remaining = totalFareMinor - payable;
    final rescueOffer = remaining - ((remaining * 10) ~/ 100);

    return BreakdownSettlement(
      farePerKm: farePerKm,
      payableMinor: payable,
      oldDriverCreditMinor: oldDriverCredit,
      remainingFareMinor: remaining,
      rescueOfferMinor: rescueOffer,
    );
  }

  Future<Map<String, Object?>> recordBreakdownAndBroadcast({
    required String breakdownId,
    required String rideId,
    required String oldDriverId,
    required int totalFareMinor,
    required double totalDistKm,
    required double coveredDistKm,
    required String idempotencyKey,
  }) async {
    final claim = await _idempotencyStore.claim(
      scope: _scopeBreakdown,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final settlement = computeBreakdownSettlement(
      totalFareMinor: totalFareMinor,
      totalDistKm: totalDistKm,
      coveredDistKm: coveredDistKm,
    );
    final now = _nowUtc();

    final result = await db.transaction((txn) async {
      await txn.insert('breakdown_events', <String, Object?>{
        'id': breakdownId,
        'ride_id': rideId,
        'old_driver_id': oldDriverId,
        'covered_dist_km': coveredDistKm,
        'total_dist_km': totalDistKm,
        'total_fare_minor': totalFareMinor,
        'payable_minor': settlement.payableMinor,
        'old_driver_credit_minor': settlement.oldDriverCreditMinor,
        'remaining_fare_minor': settlement.remainingFareMinor,
        'rescue_offer_minor': settlement.rescueOfferMinor,
        'created_at': _iso(now),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'payable_minor': settlement.payableMinor,
        'old_driver_credit_minor': settlement.oldDriverCreditMinor,
        'remaining_fare_minor': settlement.remainingFareMinor,
        'rescue_offer_minor': settlement.rescueOfferMinor,
      };
    });

    await _onBroadcast(
      rideId: rideId,
      rescueOfferMinor: settlement.rescueOfferMinor,
    );

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeBreakdown,
      key: idempotencyKey,
      resultHash: _hash(result),
    );

    return result;
  }

  static Future<void> _defaultBroadcast({
    required String rideId,
    required int rescueOfferMinor,
  }) async {
    developer.log(
      '[RESCUE_BROADCAST] ride=$rideId offer_minor=$rescueOfferMinor',
      name: 'breakdown_recovery',
    );
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hash(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }
}
