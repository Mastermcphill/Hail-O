import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/breakdown_recovery_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('breakdown algorithm math exactness', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final service = BreakdownRecoveryService(db);
    final result = service.computeBreakdownSettlement(
      totalFareMinor: 100000,
      totalDistKm: 100,
      coveredDistKm: 40,
    );
    expect(result.payableMinor, 40000);
    expect(result.oldDriverCreditMinor, 32000);
    expect(result.remainingFareMinor, 60000);
    expect(result.rescueOfferMinor, 54000);
  });

  test('record breakdown stores event and idempotent replay', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 2);
    final service = BreakdownRecoveryService(db, nowUtc: () => now);

    await db.insert('users', <String, Object?>{
      'id': 'rider_breakdown',
      'role': 'rider',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('rides', <String, Object?>{
      'id': 'ride_breakdown_1',
      'rider_id': 'rider_breakdown',
      'trip_scope': 'inter_state',
      'status': 'in_progress',
      'bidding_mode': 1,
      'base_fare_minor': 120000,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 120000,
      'connection_fee_minor': 0,
      'connection_fee_paid': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final first = await service.recordBreakdownAndBroadcast(
      breakdownId: 'breakdown_1',
      rideId: 'ride_breakdown_1',
      oldDriverId: 'driver_old_1',
      totalFareMinor: 120000,
      totalDistKm: 200,
      coveredDistKm: 100,
      idempotencyKey: 'breakdown_idem_1',
    );
    expect(first['old_driver_credit_minor'], 48000);

    final second = await service.recordBreakdownAndBroadcast(
      breakdownId: 'breakdown_1',
      rideId: 'ride_breakdown_1',
      oldDriverId: 'driver_old_1',
      totalFareMinor: 120000,
      totalDistKm: 200,
      coveredDistKm: 100,
      idempotencyKey: 'breakdown_idem_1',
    );
    expect(second['replayed'], true);
  });
}
