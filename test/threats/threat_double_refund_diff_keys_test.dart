import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/dispute_service.dart';
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
    'dispute refund with different idempotency keys only applies once',
    () async {
      final now = DateTime.utc(2026, 2, 12, 12, 0);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedSettledRide(db, now: now);

      final disputeService = DisputeService(db, nowUtc: () => now);
      await disputeService.openDispute(
        disputeId: 'dispute_refund_threat',
        rideId: 'ride_refund_threat',
        openedBy: 'rider_refund_threat',
        reason: 'refund_needed',
        idempotencyKey: 'open_dispute_refund_threat',
      );

      final first = await disputeService.resolveDispute(
        disputeId: 'dispute_refund_threat',
        resolverUserId: 'admin_refund_threat',
        resolverIsAdmin: true,
        refundMinor: 1000,
        idempotencyKey: 'resolve_dispute_refund_key_1',
        resolutionNote: 'first resolution',
      );
      final second = await disputeService.resolveDispute(
        disputeId: 'dispute_refund_threat',
        resolverUserId: 'admin_refund_threat',
        resolverIsAdmin: true,
        refundMinor: 1000,
        idempotencyKey: 'resolve_dispute_refund_key_2',
        resolutionNote: 'replay attempt',
      );

      expect(first['ok'], true);
      expect(second['ok'], true);
      expect(second['replayed'], true);

      final reversalCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM wallet_reversals'),
      )!;
      expect(reversalCount, 1);

      final disputeRows = await db.query(
        'disputes',
        columns: const <String>['refund_minor_total'],
        where: 'id = ?',
        whereArgs: const <Object>['dispute_refund_threat'],
        limit: 1,
      );
      expect(disputeRows.first['refund_minor_total'], 1000);

      final riderWalletRows = await db.query(
        'wallets',
        columns: const <String>['balance_minor'],
        where: 'owner_id = ? AND wallet_type = ?',
        whereArgs: const <Object>['rider_refund_threat', 'driver_a'],
        limit: 1,
      );
      expect((riderWalletRows.first['balance_minor'] as num).toInt(), 1000);

      final invariants = await LedgerInvariantService(db).verifySnapshot();
      expect(invariants['ok'], true, reason: invariants.toString());
    },
  );
}

Future<void> _seedSettledRide(Database db, {required DateTime now}) async {
  final nowIso = now.toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': 'rider_refund_threat',
    'role': 'rider',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': 'driver_refund_threat',
    'role': 'driver',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': 'admin_refund_threat',
    'role': 'admin',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.insert('rides', <String, Object?>{
    'id': 'ride_refund_threat',
    'rider_id': 'rider_refund_threat',
    'driver_id': 'driver_refund_threat',
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
    'id': 'escrow_refund_threat',
    'ride_id': 'ride_refund_threat',
    'holder_user_id': 'rider_refund_threat',
    'amount_minor': 10000,
    'status': 'released',
    'release_mode': 'manual_override',
    'created_at': nowIso,
    'released_at': nowIso,
    'idempotency_scope': 'seed_refund_escrow',
    'idempotency_key': 'seed_refund_escrow_key',
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await RideSettlementService(db, nowUtc: () => now).settleOnEscrowRelease(
    escrowId: 'escrow_refund_threat',
    rideId: 'ride_refund_threat',
    idempotencyKey: 'settlement:escrow_refund_threat',
    trigger: SettlementTrigger.manualOverride,
  );
}
