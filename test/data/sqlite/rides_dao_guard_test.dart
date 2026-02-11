import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/rides_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/ride_trip.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('RidesDao.createRide requires RideBookingService guard flag', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 3, 10, 9);
    final dao = RidesDao(db);

    await db.insert('users', <String, Object?>{
      'id': 'dao_guard_rider_1',
      'role': 'rider',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final ride = RideTrip(
      id: 'dao_guard_ride_1',
      riderId: 'dao_guard_rider_1',
      tripScope: TripScope.intraCity,
      status: 'pending',
      baseFareMinor: 0,
      premiumMarkupMinor: 0,
      charterMode: false,
      dailyRateMinor: 0,
      totalFareMinor: 0,
      connectionFeeMinor: 0,
      connectionFeePaid: false,
      biddingMode: true,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => dao.createRide(ride, viaRideBookingService: false),
      throwsArgumentError,
    );

    await dao.createRide(ride, viaRideBookingService: true);
    final rows = await db.query(
      'rides',
      where: 'id = ?',
      whereArgs: const <Object>['dao_guard_ride_1'],
    );
    expect(rows.length, 1);
  });

  test(
    'RidesDao.upsertAwaitingConnectionFee and markCancelled enforce guard flags',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final now = DateTime.utc(2026, 3, 10, 9);
      final nowIso = now.toIso8601String();
      final dao = RidesDao(db);

      await db.insert('users', <String, Object?>{
        'id': 'dao_guard_rider_2',
        'role': 'rider',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await db.insert('users', <String, Object?>{
        'id': 'dao_guard_driver_2',
        'role': 'driver',
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      expect(
        () => dao.upsertAwaitingConnectionFee(
          rideId: 'dao_guard_ride_2',
          riderId: 'dao_guard_rider_2',
          driverId: 'dao_guard_driver_2',
          tripScope: 'intra_city',
          feeMinor: 5000,
          bidAcceptedAtIso: nowIso,
          feeDeadlineAtIso: now
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          nowIso: nowIso,
          viaRideBookingService: false,
        ),
        throwsArgumentError,
      );

      await dao.upsertAwaitingConnectionFee(
        rideId: 'dao_guard_ride_2',
        riderId: 'dao_guard_rider_2',
        driverId: 'dao_guard_driver_2',
        tripScope: 'intra_city',
        feeMinor: 5000,
        bidAcceptedAtIso: nowIso,
        feeDeadlineAtIso: now
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        nowIso: nowIso,
        viaRideBookingService: true,
      );

      expect(
        () => dao.markCancelled(
          rideId: 'dao_guard_ride_2',
          nowIso: nowIso,
          viaCancelRideService: false,
        ),
        throwsArgumentError,
      );

      await dao.markCancelled(
        rideId: 'dao_guard_ride_2',
        nowIso: nowIso,
        viaCancelRideService: true,
      );
      final rows = await db.query(
        'rides',
        where: 'id = ?',
        whereArgs: const <Object>['dao_guard_ride_2'],
        limit: 1,
      );
      expect(rows.first['status'], 'cancelled');
    },
  );
}
