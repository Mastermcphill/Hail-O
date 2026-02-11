import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../models/latlng.dart';
import 'geo_distance.dart';

abstract class SafetyNotifier {
  Future<void> notifyInApp(String message);
  Future<void> notifySms(String phone, String message);
  Future<void> notifyWhatsApp(String phone, String message);
}

class PrintSafetyNotifier implements SafetyNotifier {
  @override
  Future<void> notifyInApp(String message) async {
    developer.log('[IN_APP] $message', name: 'safety');
  }

  @override
  Future<void> notifySms(String phone, String message) async {
    developer.log('[SMS] to=$phone message=$message', name: 'safety');
  }

  @override
  Future<void> notifyWhatsApp(String phone, String message) async {
    developer.log('[WHATSAPP] to=$phone message=$message', name: 'safety');
  }
}

class _DeviationState {
  _DeviationState();

  DateTime? startedAtUtc;
  bool sosTriggered = false;
}

class SafetyEngineService {
  SafetyEngineService(
    this.db, {
    GeoDistance? geoDistance,
    SafetyNotifier? notifier,
    DateTime Function()? nowUtc,
  }) : _geoDistance = geoDistance ?? GeoDistance(),
       _notifier = notifier ?? PrintSafetyNotifier(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _idempotencyStore = IdempotencyDao(db);

  final Database db;
  final GeoDistance _geoDistance;
  final SafetyNotifier _notifier;
  final DateTime Function() _nowUtc;
  final IdempotencyStore _idempotencyStore;

  final Map<String, _DeviationState> _deviationByRide =
      <String, _DeviationState>{};

  static const String _scopeStart = 'safety.trip.start';
  static const String _scopeArrive = 'safety.trip.arrival';
  static const String _scopeLocationSample = 'safety.location.sample';

  Future<Map<String, Object?>> onTripStarted({
    required String rideId,
    required String nextOfKinPhone,
    required String idempotencyKey,
  }) async {
    return _emitTriadEvent(
      scope: _scopeStart,
      idempotencyKey: idempotencyKey,
      rideId: rideId,
      nextOfKinPhone: nextOfKinPhone,
      eventType: 'trip_start',
      message: 'Trip started for ride $rideId',
    );
  }

  Future<Map<String, Object?>> onTripArrived({
    required String rideId,
    required String nextOfKinPhone,
    required String idempotencyKey,
  }) async {
    _deviationByRide.remove(rideId);
    return _emitTriadEvent(
      scope: _scopeArrive,
      idempotencyKey: idempotencyKey,
      rideId: rideId,
      nextOfKinPhone: nextOfKinPhone,
      eventType: 'trip_arrival',
      message: 'Trip arrived for ride $rideId',
    );
  }

  Future<Map<String, Object?>> ingestLocationSample({
    required String rideId,
    required LatLng currentPosition,
    required List<LatLng> routePolyline,
    required String nextOfKinPhone,
    required String idempotencyKey,
    DateTime? sampledAtUtc,
  }) async {
    final claim = await _idempotencyStore.claim(
      scope: _scopeLocationSample,
      key: idempotencyKey,
    );
    if (!claim.isNewClaim) {
      return <String, Object?>{
        'ok': true,
        'replayed': true,
        'result_hash': claim.record.resultHash,
      };
    }

    final sampledAt = sampledAtUtc?.toUtc() ?? _nowUtc();
    final distanceFromRoute = _geoDistance.pointToPolylineDistanceMeters(
      point: currentPosition,
      polyline: routePolyline,
    );
    final isDeviating = distanceFromRoute > 1000;

    final result = await db.transaction((txn) async {
      await txn.insert('trip_location_samples', <String, Object?>{
        'ride_id': rideId,
        'ts': _iso(sampledAt),
        'lat': currentPosition.latitude,
        'lng': currentPosition.longitude,
        'distance_from_route_m': distanceFromRoute,
        'is_deviating': isDeviating ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final state = _deviationByRide.putIfAbsent(
        rideId,
        () => _DeviationState(),
      );
      var sosTriggered = false;

      if (isDeviating) {
        state.startedAtUtc ??= sampledAt;
        final elapsed = sampledAt.difference(state.startedAtUtc!);
        if (!state.sosTriggered && elapsed > const Duration(minutes: 5)) {
          await _emitSos(
            txn: txn,
            rideId: rideId,
            nextOfKinPhone: nextOfKinPhone,
            distanceFromRoute: distanceFromRoute,
            sampledAt: sampledAt,
          );
          state.sosTriggered = true;
          sosTriggered = true;
        } else if (elapsed <= const Duration(seconds: 60)) {
          await _recordSafetyEvent(
            txn: txn,
            id: '$rideId:deviation:${sampledAt.microsecondsSinceEpoch}',
            rideId: rideId,
            eventType: 'trip_deviation',
            payload: <String, Object?>{
              'distance_from_route_m': distanceFromRoute,
              'ts': _iso(sampledAt),
            },
            createdAt: sampledAt,
          );
          await _notifier.notifyInApp('Deviation detected for ride $rideId');
          await _notifier.notifySms(
            nextOfKinPhone,
            'Deviation detected for ride $rideId',
          );
          await _notifier.notifyWhatsApp(
            nextOfKinPhone,
            'Deviation detected for ride $rideId',
          );
        }
      } else {
        state.startedAtUtc = null;
        state.sosTriggered = false;
      }

      return <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'distance_from_route_m': distanceFromRoute,
        'is_deviating': isDeviating,
        'sos_triggered': sosTriggered,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: _scopeLocationSample,
      key: idempotencyKey,
      resultHash: _hash(result),
    );
    return result;
  }

  Future<Map<String, Object?>> _emitTriadEvent({
    required String scope,
    required String idempotencyKey,
    required String rideId,
    required String nextOfKinPhone,
    required String eventType,
    required String message,
  }) async {
    final claim = await _idempotencyStore.claim(
      scope: scope,
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
      await _recordSafetyEvent(
        txn: txn,
        id: '$rideId:$eventType:${now.microsecondsSinceEpoch}',
        rideId: rideId,
        eventType: eventType,
        payload: <String, Object?>{
          'message': message,
          'next_of_kin_phone': nextOfKinPhone,
        },
        createdAt: now,
      );

      await _notifier.notifyInApp(message);
      await _notifier.notifySms(nextOfKinPhone, message);
      await _notifier.notifyWhatsApp(nextOfKinPhone, message);

      return <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'event_type': eventType,
      };
    });

    await _idempotencyStore.finalizeSuccess(
      scope: scope,
      key: idempotencyKey,
      resultHash: _hash(result),
    );
    return result;
  }

  Future<void> _emitSos({
    required Transaction txn,
    required String rideId,
    required String nextOfKinPhone,
    required double distanceFromRoute,
    required DateTime sampledAt,
  }) async {
    final message =
        'SOS: deviation >1km for >5min on ride $rideId (${distanceFromRoute.toStringAsFixed(1)}m)';
    await _recordSafetyEvent(
      txn: txn,
      id: '$rideId:sos:${sampledAt.microsecondsSinceEpoch}',
      rideId: rideId,
      eventType: 'sos_deviation',
      payload: <String, Object?>{
        'distance_from_route_m': distanceFromRoute,
        'ts': _iso(sampledAt),
      },
      createdAt: sampledAt,
    );
    await _notifier.notifyInApp(message);
    await _notifier.notifySms(nextOfKinPhone, message);
    await _notifier.notifyWhatsApp(nextOfKinPhone, message);
  }

  Future<void> _recordSafetyEvent({
    required Transaction txn,
    required String id,
    required String rideId,
    required String eventType,
    required Map<String, Object?> payload,
    required DateTime createdAt,
  }) {
    return txn.insert('safety_events', <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'event_type': eventType,
      'payload_json': jsonEncode(payload),
      'created_at': _iso(createdAt),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String _hash(Map<String, Object?> result) {
    return sha256.convert(utf8.encode(jsonEncode(result))).toString();
  }
}
