import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../errors/domain_errors.dart';
import 'finance_utils.dart';
import 'ride_lifecycle_guard_service.dart';

class AcceptRideService {
  AcceptRideService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;
  static const RideLifecycleGuardService _lifecycleGuard =
      RideLifecycleGuardService();

  static const String _scopeAcceptRide = 'ride_acceptance';

  Future<Map<String, Object?>> acceptRide({
    required String rideId,
    required String driverId,
    required String idempotencyKey,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeAcceptRide,
      key: idempotencyKey,
      requestHash: '$rideId|$driverId',
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': claim.record.status.dbValue == 'success',
        'replayed': true,
        'result_hash': claim.record.resultHash,
        'error': claim.record.errorCode,
      };
    }

    try {
      final now = _nowUtc();
      final nowIso = isoNowUtc(now);
      final result = await db.transaction((txn) async {
        return _acceptOnExecutor(
          txn,
          rideId: rideId,
          driverId: driverId,
          nowIso: nowIso,
        );
      });

      final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeAcceptRide,
        key: idempotencyKey,
        resultHash: hash,
      );
      return <String, Object?>{...result, 'result_hash': hash};
    } catch (e) {
      final code = e is DomainError ? e.code : 'accept_ride_exception';
      await _idempotencyStore.finalizeFailure(
        scope: _scopeAcceptRide,
        key: idempotencyKey,
        errorCode: code,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> acceptRideWithExecutor(
    DatabaseExecutor executor, {
    required String rideId,
    required String driverId,
    required String idempotencyKey,
  }) async {
    final nowIso = isoNowUtc(_nowUtc());
    return _acceptOnExecutor(
      executor,
      rideId: rideId,
      driverId: driverId,
      nowIso: nowIso,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<Map<String, Object?>> _acceptOnExecutor(
    DatabaseExecutor executor, {
    required String rideId,
    required String driverId,
    required String nowIso,
    String? idempotencyKey,
  }) async {
    final ridesDao = RidesDao(executor);
    final ride = await ridesDao.findById(rideId);
    if (ride == null) {
      throw const DomainInvariantError(code: 'ride_not_found');
    }

    final currentStatus = (ride['status'] as String?) ?? '';
    final currentDriver = (ride['driver_id'] as String?)?.trim() ?? '';
    if (currentStatus.trim().toLowerCase() == 'accepted') {
      if (currentDriver == driverId) {
        return <String, Object?>{
          'ok': true,
          'ride_id': rideId,
          'driver_id': driverId,
          'status': 'accepted',
          'replayed': true,
        };
      }
      throw const DomainInvariantError(code: 'ride_already_accepted');
    }

    try {
      _lifecycleGuard.assertCanAccept(currentStatus);
    } on RideLifecycleViolation catch (e) {
      throw LifecycleViolationError(
        code: e.code,
        metadata: <String, Object?>{'status': e.status, 'ride_id': rideId},
      );
    }

    final changed = await ridesDao.markAccepted(
      rideId: rideId,
      driverId: driverId,
      acceptedAtIso: nowIso,
      nowIso: nowIso,
      viaAcceptRideService: true,
    );
    if (changed == 0) {
      final refreshed = await ridesDao.findById(rideId);
      final refreshedDriver =
          (refreshed?['driver_id'] as String?)?.trim() ?? '';
      if ((refreshed?['status'] as String?) == 'accepted' &&
          refreshedDriver == driverId) {
        return <String, Object?>{
          'ok': true,
          'ride_id': rideId,
          'driver_id': driverId,
          'status': 'accepted',
          'replayed': true,
        };
      }
      throw const DomainInvariantError(code: 'ride_acceptance_race_lost');
    }

    return <String, Object?>{
      'ok': true,
      'ride_id': rideId,
      'driver_id': driverId,
      'status': 'accepted',
      'accepted_at': nowIso,
      'idempotency_key': idempotencyKey,
      'replayed': false,
    };
  }
}
