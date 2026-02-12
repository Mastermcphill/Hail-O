import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/escrow_holds_dao.dart';
import '../../data/sqlite/dao/idempotency_dao.dart';
import '../models/latlng.dart';
import 'geo_distance.dart';
import 'operation_journal_service.dart';
import 'ride_settlement_service.dart';

class EscrowService {
  EscrowService(
    this.db, {
    GeoDistance? geoDistance,
    RideSettlementService? rideSettlementService,
    DateTime Function()? nowUtc,
    OperationJournalService? operationJournalService,
  }) : _geoDistance = geoDistance ?? GeoDistance(),
       _rideSettlementService =
           rideSettlementService ?? RideSettlementService(db, nowUtc: nowUtc),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db),
       _operationJournalService =
           operationJournalService ??
           OperationJournalService(db, nowUtc: nowUtc);

  final Database db;
  final GeoDistance _geoDistance;
  final RideSettlementService _rideSettlementService;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;
  final OperationJournalService _operationJournalService;

  static const String _scopeGeofenceRelease = 'escrow.release.geofence';
  static const String _scopeManualRelease = 'escrow.release.manual';

  Future<Map<String, Object?>> releaseOnArrival({
    required String escrowId,
    required LatLng driverPosition,
    required LatLng riderDestination,
    required String idempotencyKey,
    double geofenceRadiusMeters = 150,
    String? settlementIdempotencyKey,
  }) {
    return releaseOnGeofenceArrival(
      escrowId: escrowId,
      driverPosition: driverPosition,
      riderDestination: riderDestination,
      idempotencyKey: idempotencyKey,
      geofenceRadiusMeters: geofenceRadiusMeters,
      settlementIdempotencyKey: settlementIdempotencyKey,
    );
  }

  Future<Map<String, Object?>> releaseOnGeofenceArrival({
    required String escrowId,
    required LatLng driverPosition,
    required LatLng riderDestination,
    required String idempotencyKey,
    double geofenceRadiusMeters = 150,
    String? settlementIdempotencyKey,
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

    try {
      await _operationJournalService.begin(
        opType: 'SETTLE',
        entityType: 'escrow',
        entityId: escrowId,
        idempotencyScope: _scopeGeofenceRelease,
        idempotencyKey: idempotencyKey,
        traceId: 'trace:$_scopeGeofenceRelease:$idempotencyKey',
        metadataJson:
            '{"release_mode":"geofence","escrow_id":"$escrowId","geofence_radius_m":$geofenceRadiusMeters}',
      );

      final distance = _geoDistance.haversineMeters(
        driverPosition,
        riderDestination,
      );
      final now = _nowUtc();
      var result = await db.transaction((txn) async {
        final escrowDao = EscrowHoldsDao(txn);
        final escrow = await escrowDao.findById(escrowId);
        if (escrow == null) {
          return <String, Object?>{
            'ok': false,
            'released': false,
            'reason': 'escrow_not_found',
          };
        }

        if (escrow.status != 'held') {
          return <String, Object?>{
            'ok': true,
            'released': false,
            'reason': 'already_processed',
            'status': escrow.status,
            'ride_id': escrow.rideId,
          };
        }

        if (distance > geofenceRadiusMeters) {
          return <String, Object?>{
            'ok': true,
            'released': false,
            'reason': 'geofence_not_matched',
            'distance_m': distance,
            'ride_id': escrow.rideId,
          };
        }

        await escrowDao.markReleasedIfHeld(
          escrowId: escrowId,
          releaseMode: 'geofence',
          releasedAtIso: _iso(now),
          idempotencyScope: _scopeGeofenceRelease,
          idempotencyKey: idempotencyKey,
          viaOrchestrator: true,
        );
        return <String, Object?>{
          'ok': true,
          'released': true,
          'release_mode': 'geofence',
          'distance_m': distance,
          'ride_id': escrow.rideId,
        };
      });

      final shouldSettle =
          result['ok'] == true &&
          ((result['released'] == true) || (result['status'] == 'released'));
      final rideId = (result['ride_id'] as String?) ?? '';
      if (shouldSettle && rideId.isNotEmpty) {
        final settlement = await _rideSettlementService.settleOnEscrowRelease(
          escrowId: escrowId,
          rideId: rideId,
          idempotencyKey: _resolveSettlementIdempotencyKey(
            escrowId,
            settlementIdempotencyKey,
          ),
          trigger: SettlementTrigger.arrivalGeofence,
        );
        result = <String, Object?>{...result, 'settlement': settlement.toMap()};
      }

      await _idempotencyStore.finalizeSuccess(
        scope: _scopeGeofenceRelease,
        key: idempotencyKey,
        resultHash: _hash(result),
      );
      await _operationJournalService.commit(
        idempotencyScope: _scopeGeofenceRelease,
        idempotencyKey: idempotencyKey,
      );
      return result;
    } catch (error) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeGeofenceRelease,
        key: idempotencyKey,
        errorCode: 'escrow_geofence_release_exception',
      );
      await _operationJournalService.fail(
        idempotencyScope: _scopeGeofenceRelease,
        idempotencyKey: idempotencyKey,
        errorMessage: _safeError(error),
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> releaseOnManualOverride({
    required String escrowId,
    required String riderId,
    required String idempotencyKey,
    String? settlementIdempotencyKey,
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

    try {
      await _operationJournalService.begin(
        opType: 'SETTLE',
        entityType: 'escrow',
        entityId: escrowId,
        idempotencyScope: _scopeManualRelease,
        idempotencyKey: idempotencyKey,
        traceId: 'trace:$_scopeManualRelease:$idempotencyKey',
        metadataJson:
            '{"release_mode":"manual_override","escrow_id":"$escrowId","rider_id":"$riderId"}',
      );

      final now = _nowUtc();
      var result = await db.transaction((txn) async {
        final escrowDao = EscrowHoldsDao(txn);
        final escrow = await escrowDao.findById(escrowId);
        if (escrow == null) {
          return <String, Object?>{
            'ok': false,
            'released': false,
            'reason': 'escrow_not_found',
          };
        }

        if (escrow.status != 'held') {
          return <String, Object?>{
            'ok': true,
            'released': false,
            'reason': 'already_processed',
            'status': escrow.status,
            'ride_id': escrow.rideId,
          };
        }

        await escrowDao.markReleasedIfHeld(
          escrowId: escrowId,
          releaseMode: 'manual_override',
          releasedAtIso: _iso(now),
          idempotencyScope: _scopeManualRelease,
          idempotencyKey: idempotencyKey,
          viaOrchestrator: true,
        );
        return <String, Object?>{
          'ok': true,
          'released': true,
          'release_mode': 'manual_override',
          'rider_id': riderId,
          'ride_id': escrow.rideId,
        };
      });

      final shouldSettle =
          result['ok'] == true &&
          ((result['released'] == true) || (result['status'] == 'released'));
      final rideId = (result['ride_id'] as String?) ?? '';
      if (shouldSettle && rideId.isNotEmpty) {
        final settlement = await _rideSettlementService.settleOnEscrowRelease(
          escrowId: escrowId,
          rideId: rideId,
          idempotencyKey: _resolveSettlementIdempotencyKey(
            escrowId,
            settlementIdempotencyKey,
          ),
          trigger: SettlementTrigger.manualOverride,
        );
        result = <String, Object?>{...result, 'settlement': settlement.toMap()};
      }

      await _idempotencyStore.finalizeSuccess(
        scope: _scopeManualRelease,
        key: idempotencyKey,
        resultHash: _hash(result),
      );
      await _operationJournalService.commit(
        idempotencyScope: _scopeManualRelease,
        idempotencyKey: idempotencyKey,
      );
      return result;
    } catch (error) {
      await _idempotencyStore.finalizeFailure(
        scope: _scopeManualRelease,
        key: idempotencyKey,
        errorCode: 'escrow_manual_release_exception',
      );
      await _operationJournalService.fail(
        idempotencyScope: _scopeManualRelease,
        idempotencyKey: idempotencyKey,
        errorMessage: _safeError(error),
      );
      rethrow;
    }
  }

  String _resolveSettlementIdempotencyKey(
    String escrowId,
    String? providedIdempotencyKey,
  ) {
    final provided = providedIdempotencyKey?.trim() ?? '';
    if (provided.isNotEmpty) {
      return provided;
    }
    return 'settlement:$escrowId';
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hash(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }

  String _safeError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) {
      return 'escrow_release_unknown_error';
    }
    if (text.length > 500) {
      return text.substring(0, 500);
    }
    return text;
  }
}
