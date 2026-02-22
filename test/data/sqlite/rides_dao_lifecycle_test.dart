import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/rides_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('markConnectionFeePaid enforces lifecycle status', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 3, 11, 8);
    final nowIso = now.toIso8601String();
    final dao = RidesDao(db);

    await db.insert('users', <String, Object?>{
      'id': 'lifecycle_rider_1',
      'role': 'rider',
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    await db.insert('rides', <String, Object?>{
      'id': 'lifecycle_ride_1',
      'rider_id': 'lifecycle_rider_1',
      'trip_scope': 'intra_city',
      'status': 'pending',
      'bidding_mode': 1,
      'base_fare_minor': 0,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 0,
      'connection_fee_minor': 5000,
      'connection_fee_paid': 0,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    expect(
      () => dao.markConnectionFeePaid(
        rideId: 'lifecycle_ride_1',
        nowIso: nowIso,
        viaWalletService: true,
      ),
      throwsA(isA<Exception>()),
    );

    await db.update(
      'rides',
      <String, Object?>{'status': 'awaiting_connection_fee'},
      where: 'id = ?',
      whereArgs: const <Object>['lifecycle_ride_1'],
    );
    await dao.markConnectionFeePaid(
      rideId: 'lifecycle_ride_1',
      nowIso: nowIso,
      viaWalletService: true,
    );
    final ride = await dao.findById('lifecycle_ride_1');
    expect(ride?['status'], 'connection_fee_paid');
  });

  test('updateFinanceIfExists blocks cancelled rides', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 3, 11, 8);
    final nowIso = now.toIso8601String();
    final dao = RidesDao(db);

    await db.insert('users', <String, Object?>{
      'id': 'lifecycle_rider_2',
      'role': 'rider',
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    await db.insert('rides', <String, Object?>{
      'id': 'lifecycle_ride_2',
      'rider_id': 'lifecycle_rider_2',
      'trip_scope': 'intra_city',
      'status': 'cancelled',
      'bidding_mode': 1,
      'base_fare_minor': 0,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 0,
      'connection_fee_minor': 0,
      'connection_fee_paid': 0,
      'cancelled_at': nowIso,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    expect(
      () => dao.updateFinanceIfExists(
        rideId: 'lifecycle_ride_2',
        baseFareMinor: 1000,
        premiumSeatMarkupMinor: 100,
        nowIso: nowIso,
        viaFinanceSettlementService: true,
      ),
      throwsA(isA<Exception>()),
    );
  });
}
