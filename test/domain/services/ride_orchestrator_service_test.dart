import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/data/sqlite/hailo_database.dart';
import 'package:hailo_core/domain/models/ride_event_type.dart';
import 'package:hailo_core/domain/services/ride_lifecycle_guard_service.dart';
import 'package:hailo_core/domain/services/ride_orchestrator_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RideOrchestratorService', () {
    test(
      'ride booked event is replay-safe and writes one ride_event',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        await _seedRiderWithNextOfKin(db, riderId: 'rider_orch_1', now: now);

        final orchestrator = RideOrchestratorService(db, nowUtc: () => now);
        final first = await orchestrator.applyEvent(
          eventType: RideEventType.rideBooked,
          rideId: 'ride_orch_1',
          idempotencyKey: 'ride_event_book_1',
          actorId: 'rider_orch_1',
          payload: <String, Object?>{
            'rider_id': 'rider_orch_1',
            'trip_scope': 'intra_city',
            'distance_meters': 12000,
            'duration_seconds': 1800,
            'luggage_count': 1,
            'vehicle_class': 'sedan',
            'base_fare_minor': 10000,
          },
        );
        final second = await orchestrator.applyEvent(
          eventType: RideEventType.rideBooked,
          rideId: 'ride_orch_1',
          idempotencyKey: 'ride_event_book_1',
          actorId: 'rider_orch_1',
          payload: <String, Object?>{
            'rider_id': 'rider_orch_1',
            'trip_scope': 'intra_city',
            'distance_meters': 12000,
            'duration_seconds': 1800,
            'luggage_count': 1,
            'vehicle_class': 'sedan',
            'base_fare_minor': 10000,
          },
        );

        expect(first['ok'], true);
        expect(second['replayed'], true);

        final rideRows = await db.query(
          'rides',
          where: 'id = ?',
          whereArgs: const <Object>['ride_orch_1'],
        );
        final eventRows = await db.query(
          'ride_events',
          where: 'ride_id = ?',
          whereArgs: const <Object>['ride_orch_1'],
        );

        expect(rideRows.length, 1);
        expect(eventRows.length, 1);
        expect(eventRows.first['event_type'], 'RIDE_BOOKED');
      },
    );

    test('ride booked normalizes client-provided fare fields', () async {
      final now = DateTime.utc(2026, 2, 11, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedRiderWithNextOfKin(db, riderId: 'rider_orch_3', now: now);

      final orchestrator = RideOrchestratorService(db, nowUtc: () => now);
      await orchestrator.applyEvent(
        eventType: RideEventType.rideBooked,
        rideId: 'ride_orch_3',
        idempotencyKey: 'ride_event_book_normalize_1',
        actorId: 'rider_orch_3',
        payload: <String, Object?>{
          'rider_id': 'rider_orch_3',
          'trip_scope': 'intra_city',
          'distance_meters': 5000,
          'duration_seconds': 900,
          'luggage_count': 0,
          'vehicle_class': 'sedan',
          'base_fare_minor': 999999,
          'premium_markup_minor': -2000,
          'connection_fee_minor': -100,
        },
      );

      final rideRows = await db.query(
        'rides',
        columns: <String>[
          'base_fare_minor',
          'premium_markup_minor',
          'connection_fee_minor',
          'quoted_fare_minor',
        ],
        where: 'id = ?',
        whereArgs: const <Object>['ride_orch_3'],
        limit: 1,
      );

      expect(rideRows, isNotEmpty);
      final ride = rideRows.first;
      expect(ride['base_fare_minor'], 15000);
      expect(ride['premium_markup_minor'], 0);
      expect(ride['connection_fee_minor'], 0);
      expect((ride['quoted_fare_minor'] as int?) ?? 0, greaterThan(0));
    });

    test('invalid transition rejects start before accept', () async {
      final now = DateTime.utc(2026, 2, 11, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedRiderWithNextOfKin(db, riderId: 'rider_orch_2', now: now);
      await db.insert('rides', <String, Object?>{
        'id': 'ride_orch_2',
        'rider_id': 'rider_orch_2',
        'trip_scope': 'intra_city',
        'status': 'pending',
        'bidding_mode': 1,
        'base_fare_minor': 0,
        'premium_markup_minor': 0,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 0,
        'connection_fee_minor': 0,
        'connection_fee_paid': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final orchestrator = RideOrchestratorService(db, nowUtc: () => now);
      expect(
        () => orchestrator.applyEvent(
          eventType: RideEventType.rideStarted,
          rideId: 'ride_orch_2',
          idempotencyKey: 'ride_event_start_invalid',
          actorId: 'driver_orch_2',
        ),
        throwsA(isA<RideLifecycleViolation>()),
      );

      final replay = await orchestrator.applyEvent(
        eventType: RideEventType.rideStarted,
        rideId: 'ride_orch_2',
        idempotencyKey: 'ride_event_start_invalid',
        actorId: 'driver_orch_2',
      );
      expect(replay['ok'], false);
      expect(replay['replayed'], true);

      final eventRows = await db.query(
        'ride_events',
        where: 'ride_id = ?',
        whereArgs: const <Object>['ride_orch_2'],
      );
      expect(eventRows, isEmpty);
    });
  });
}

Future<void> _seedRiderWithNextOfKin(
  dynamic db, {
  required String riderId,
  required DateTime now,
}) async {
  await db.insert('users', <String, Object?>{
    'id': riderId,
    'role': 'rider',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
  await db.insert('next_of_kin', <String, Object?>{
    'user_id': riderId,
    'full_name': 'Kin Rider',
    'phone': '+234000000100',
    'relationship': 'sibling',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
