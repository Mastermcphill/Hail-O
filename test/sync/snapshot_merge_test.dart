import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/cancel_ride_service.dart';
import 'package:hail_o_finance_core/domain/services/dispute_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_settlement_service.dart';
import 'package:hail_o_finance_core/domain/services/sync_snapshot_service.dart';
import 'package:hail_o_finance_core/domain/services/wallet_reversal_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('snapshot merge keeps unique union and preserves invariants', () async {
    final now = DateTime.utc(2026, 2, 12, 9, 0);

    final dbA = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    final dbB = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    final mergedAB = await HailODatabase().open(
      databasePath: inMemoryDatabasePath,
    );
    final mergedBA = await HailODatabase().open(
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
      await mergedAB.close();
      await mergedBA.close();
    });

    await _seedSharedSettlementScenario(dbA, now: now, idSuffix: 'A');
    await _seedSharedSettlementScenario(dbB, now: now, idSuffix: 'B');
    await _seedCancellationScenario(dbB, now: now);

    final snapshotA = await SyncSnapshotService(dbA).exportSnapshot();
    final snapshotB = await SyncSnapshotService(dbB).exportSnapshot();

    final importAb1 = await SyncSnapshotService(
      mergedAB,
    ).importSnapshot(snapshotA);
    expect(importAb1['ok'], true, reason: importAb1.toString());
    final importAb2 = await SyncSnapshotService(
      mergedAB,
    ).importSnapshot(snapshotB);
    expect(importAb2['ok'], true, reason: importAb2.toString());

    final importBa1 = await SyncSnapshotService(
      mergedBA,
    ).importSnapshot(snapshotB);
    expect(importBa1['ok'], true, reason: importBa1.toString());
    final importBa2 = await SyncSnapshotService(
      mergedBA,
    ).importSnapshot(snapshotA);
    expect(importBa2['ok'], true, reason: importBa2.toString());

    await _assertMergedCounts(mergedAB);
    await _assertMergedCounts(mergedBA);
  });
}

Future<void> _seedSharedSettlementScenario(
  Database db, {
  required DateTime now,
  required String idSuffix,
}) async {
  final nowIso = now.toIso8601String();
  await _upsertUser(db, userId: 'rider_sync', role: 'rider', nowIso: nowIso);
  await _upsertUser(db, userId: 'driver_sync', role: 'driver', nowIso: nowIso);
  await _upsertUser(db, userId: 'admin_sync', role: 'admin', nowIso: nowIso);

  await db.insert('rides', <String, Object?>{
    'id': 'ride_sync',
    'rider_id': 'rider_sync',
    'driver_id': 'driver_sync',
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
    'id': 'escrow_sync',
    'ride_id': 'ride_sync',
    'holder_user_id': 'rider_sync',
    'amount_minor': 10000,
    'status': 'released',
    'release_mode': 'manual_override',
    'created_at': nowIso,
    'released_at': nowIso,
    'idempotency_scope': 'seed_escrow',
    'idempotency_key': 'seed_escrow_sync',
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await RideSettlementService(db, nowUtc: () => now).settleOnEscrowRelease(
    escrowId: 'escrow_sync',
    rideId: 'ride_sync',
    idempotencyKey: 'settlement:escrow_sync',
    trigger: SettlementTrigger.manualOverride,
  );

  final creditRows = await db.query(
    'wallet_ledger',
    columns: const <String>['id'],
    where: 'reference_id = ? AND direction = ?',
    whereArgs: const <Object>['ride_sync', 'credit'],
    orderBy: 'id ASC',
    limit: 1,
  );
  final originalLedgerId = (creditRows.first['id'] as num).toInt();
  await WalletReversalService(db, nowUtc: () => now).reverseWalletLedgerEntry(
    originalLedgerId: originalLedgerId,
    requestedByUserId: 'admin_sync',
    requesterIsAdmin: true,
    reason: 'sync_reversal',
    idempotencyKey: 'sync_reversal_$idSuffix',
  );

  await DisputeService(db, nowUtc: () => now).openDispute(
    disputeId: 'dispute_sync',
    rideId: 'ride_sync',
    openedBy: 'rider_sync',
    reason: 'sync_issue',
    idempotencyKey: 'sync_dispute_open_$idSuffix',
  );
}

Future<void> _seedCancellationScenario(
  Database db, {
  required DateTime now,
}) async {
  final nowIso = now.toIso8601String();
  await _upsertUser(
    db,
    userId: 'rider_cancel_sync',
    role: 'rider',
    nowIso: nowIso,
  );
  await db.insert('rides', <String, Object?>{
    'id': 'ride_cancel_sync',
    'rider_id': 'rider_cancel_sync',
    'driver_id': null,
    'trip_scope': 'intra_city',
    'status': 'pending',
    'bidding_mode': 1,
    'base_fare_minor': 5000,
    'premium_markup_minor': 0,
    'charter_mode': 0,
    'daily_rate_minor': 0,
    'total_fare_minor': 5000,
    'connection_fee_minor': 0,
    'connection_fee_paid': 0,
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await CancelRideService(db, nowUtc: () => now).collectCancellationPenalty(
    rideId: 'ride_cancel_sync',
    payerUserId: 'rider_cancel_sync',
    penaltyMinor: 0,
    idempotencyKey: 'sync_cancel_penalty',
    ruleCode: 'sync_cancel',
  );
}

Future<void> _assertMergedCounts(Database db) async {
  final payouts = Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM payout_records WHERE escrow_id = ?',
      const <Object>['escrow_sync'],
    ),
  )!;
  expect(payouts, 1);

  final reversals = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM wallet_reversals'),
  )!;
  expect(reversals, 1);

  final disputes = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM disputes WHERE id = ?', <Object>[
      'dispute_sync',
    ]),
  )!;
  expect(disputes, 1);

  final penaltyRows = Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM penalty_records WHERE ride_id = ?',
      const <Object>['ride_cancel_sync'],
    ),
  )!;
  expect(penaltyRows, 1);
}

Future<void> _upsertUser(
  Database db, {
  required String userId,
  required String role,
  required String nowIso,
}) async {
  await db.insert('users', <String, Object?>{
    'id': userId,
    'role': role,
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}
