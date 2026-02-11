import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/services/accept_ride_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('accept ride is idempotent and race-safe across drivers', () async {
    final now = DateTime.utc(2026, 2, 11, 12);
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    await db.insert('users', <String, Object?>{
      'id': 'rider_accept',
      'role': 'rider',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('users', <String, Object?>{
      'id': 'driver_accept_1',
      'role': 'driver',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('users', <String, Object?>{
      'id': 'driver_accept_2',
      'role': 'driver',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert('rides', <String, Object?>{
      'id': 'ride_accept_1',
      'rider_id': 'rider_accept',
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

    final service = AcceptRideService(db, nowUtc: () => now);

    final first = await service.acceptRide(
      rideId: 'ride_accept_1',
      driverId: 'driver_accept_1',
      idempotencyKey: 'accept_key_1',
    );
    final replay = await service.acceptRide(
      rideId: 'ride_accept_1',
      driverId: 'driver_accept_1',
      idempotencyKey: 'accept_key_1',
    );

    expect(first['ok'], true);
    expect(first['status'], 'accepted');
    expect(replay['ok'], true);
    expect(replay['replayed'], true);

    expect(
      () => service.acceptRide(
        rideId: 'ride_accept_1',
        driverId: 'driver_accept_2',
        idempotencyKey: 'accept_key_2',
      ),
      throwsA(
        isA<DomainInvariantError>().having(
          (e) => e.code,
          'code',
          'ride_already_accepted',
        ),
      ),
    );
  });
}
