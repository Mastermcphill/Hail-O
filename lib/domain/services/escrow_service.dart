import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../models/latlng.dart';
import 'geo_distance.dart';

class EscrowService {
  EscrowService(
    this.db, {
    GeoDistance? geoDistance,
    DateTime Function()? nowUtc,
  }) : _geoDistance = geoDistance ?? GeoDistance(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final GeoDistance _geoDistance;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  static const String _scopeGeofenceRelease = 'escrow.release.geofence';
  static const String _scopeManualRelease = 'escrow.release.manual';

  Future<Map<String, Object?>> releaseOnGeofenceArrival({
    required String escrowId,
    required LatLng driverPosition,
    required LatLng riderDestination,
    required String idempotencyKey,
    double geofenceRadiusMeters = 150,
  }) async {
    final claim = await _idempotencyStore.claim(
      scope: _scopeGeofenceRelease,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final distance = _geoDistance.haversineMeters(
      driverPosition,
      riderDestination,
    );
    final now = _nowUtc();
    final result = await db.transaction((txn) async {
      final rows = await txn.query(
        'escrow_holds',
        where: 'id = ?',
        whereArgs: <Object>[escrowId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return <String, Object?>{
          'ok': false,
          'released': false,
          'reason': 'escrow_not_found',
        };
      }

      final row = rows.first;
      final status = row['status'] as String? ?? 'held';
      if (status != 'held') {
        return <String, Object?>{
          'ok': true,
          'released': false,
          'reason': 'already_processed',
          'status': status,
        };
      }

      if (distance > geofenceRadiusMeters) {
        return <String, Object?>{
          'ok': true,
          'released': false,
          'reason': 'geofence_not_matched',
          'distance_m': distance,
        };
      }

      await txn.update(
        'escrow_holds',
        <String, Object?>{
          'status': 'released',
          'release_mode': 'geofence',
          'released_at': _iso(now),
          'idempotency_scope': _scopeGeofenceRelease,
          'idempotency_key': idempotencyKey,
        },
        where: 'id = ?',
        whereArgs: <Object>[escrowId],
      );
      return <String, Object?>{
        'ok': true,
        'released': true,
        'release_mode': 'geofence',
        'distance_m': distance,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeGeofenceRelease,
      key: idempotencyKey,
      resultHash: _hash(result),
    );
    return result;
  }

  Future<Map<String, Object?>> releaseOnManualOverride({
    required String escrowId,
    required String riderId,
    required String idempotencyKey,
  }) async {
    final claim = await _idempotencyStore.claim(
      scope: _scopeManualRelease,
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
      final rows = await txn.query(
        'escrow_holds',
        where: 'id = ?',
        whereArgs: <Object>[escrowId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return <String, Object?>{
          'ok': false,
          'released': false,
          'reason': 'escrow_not_found',
        };
      }

      final row = rows.first;
      final status = row['status'] as String? ?? 'held';
      if (status != 'held') {
        return <String, Object?>{
          'ok': true,
          'released': false,
          'reason': 'already_processed',
          'status': status,
        };
      }

      await txn.update(
        'escrow_holds',
        <String, Object?>{
          'status': 'released',
          'release_mode': 'manual_override',
          'released_at': _iso(now),
          'idempotency_scope': _scopeManualRelease,
          'idempotency_key': idempotencyKey,
        },
        where: 'id = ?',
        whereArgs: <Object>[escrowId],
      );
      return <String, Object?>{
        'ok': true,
        'released': true,
        'release_mode': 'manual_override',
        'rider_id': riderId,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeManualRelease,
      key: idempotencyKey,
      resultHash: _hash(result),
    );
    return result;
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hash(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }
}
