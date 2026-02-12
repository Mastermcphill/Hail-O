import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/escrow_service.dart';
import 'package:hail_o_finance_core/domain/services/ledger_invariant_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_settlement_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'settle same escrow from two entrypoints with different keys only pays once',
    () async {
      final now = DateTime.utc(2026, 2, 12, 11, 0);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedRideWithHeldEscrow(db, now: now);

      final settlementService = RideSettlementService(db, nowUtc: () => now);
      final escrowService = EscrowService(
        db,
        rideSettlementService: settlementService,
        nowUtc: () => now,
      );

      final released = await escrowService.releaseOnManualOverride(
        escrowId: 'escrow_settle_threat',
        riderId: 'rider_settle_threat',
        idempotencyKey: 'manual_release_threat',
      );
      expect(released['released'], true);

      final second = await settlementService.settleOnEscrowRelease(
        escrowId: 'escrow_settle_threat',
        rideId: 'ride_settle_threat',
        idempotencyKey: 'different_key_second_entrypoint',
        trigger: SettlementTrigger.manualOverride,
      );
      expect(second.ok, true);
      expect(second.replayed, true);

      final payoutCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM payout_records WHERE escrow_id = ?',
          const <Object>['escrow_settle_threat'],
        ),
      )!;
      expect(payoutCount, 1);

      final invariants = await LedgerInvariantService(db).verifySnapshot();
      expect(invariants['ok'], true, reason: invariants.toString());
    },
  );
}

Future<void> _seedRideWithHeldEscrow(
  Database db, {
  required DateTime now,
}) async {
  final nowIso = now.toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': 'rider_settle_threat',
    'role': 'rider',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': 'driver_settle_threat',
    'role': 'driver',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.insert('rides', <String, Object?>{
    'id': 'ride_settle_threat',
    'rider_id': 'rider_settle_threat',
    'driver_id': 'driver_settle_threat',
    'trip_scope': 'intra_city',
    'status': 'completed',
    'bidding_mode': 1,
    'base_fare_minor': 10000,
    'premium_markup_minor': 0,
    'charter_mode': 0,
    'daily_rate_minor': 0,
    'total_fare_minor': 10000,
    'connection_fee_minor': 0,
    'connection_fee_paid': 1,
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('escrow_holds', <String, Object?>{
    'id': 'escrow_settle_threat',
    'ride_id': 'ride_settle_threat',
    'holder_user_id': 'rider_settle_threat',
    'amount_minor': 10000,
    'status': 'held',
    'created_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
