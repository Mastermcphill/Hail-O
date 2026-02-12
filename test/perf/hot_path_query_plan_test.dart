import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_query_plan.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('hot path queries use indexes on large synthetic dataset', () async {
    final now = DateTime.utc(2026, 2, 12, 6, 0);
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    await _seedLargeDataset(db, now);

    final pricingPlan = await explainQueryPlan(
      db,
      sql:
          'SELECT version FROM pricing_rules '
          'WHERE scope = ? AND effective_from <= ? '
          'ORDER BY effective_from DESC, version DESC LIMIT 1',
      args: <Object?>['default', now.toIso8601String()],
    );
    expect(
      queryPlanUsesIndex(
        pricingPlan,
        indexName: 'idx_pricing_rules_scope_effective',
      ),
      true,
      reason: pricingPlan.join('\n'),
    );

    final compliancePlan = await explainQueryPlan(
      db,
      sql:
          'SELECT required_docs_json FROM compliance_requirements '
          'WHERE scope = ? AND from_country = ? AND to_country = ? LIMIT 1',
      args: const <Object?>['international', 'NG', 'GH'],
    );
    expect(
      queryPlanUsesIndex(compliancePlan),
      true,
      reason: compliancePlan.join('\n'),
    );

    final ledgerPlan = await explainQueryPlan(
      db,
      sql:
          'SELECT id, amount_minor FROM wallet_ledger '
          'WHERE owner_id = ? AND wallet_type = ? '
          'ORDER BY created_at DESC LIMIT 100',
      args: const <Object?>['driver_perf_3', 'driver_a'],
    );
    expect(
      queryPlanUsesIndex(
        ledgerPlan,
        indexName: 'idx_wallet_ledger_owner_created',
      ),
      true,
      reason: ledgerPlan.join('\n'),
    );

    final rideEventsPlan = await explainQueryPlan(
      db,
      sql:
          'SELECT id, event_type FROM ride_events '
          'WHERE ride_id = ? ORDER BY created_at DESC LIMIT 100',
      args: const <Object?>['ride_perf_9999'],
    );
    expect(
      queryPlanUsesIndex(
        rideEventsPlan,
        indexName: 'idx_ride_events_ride_created',
      ),
      true,
      reason: rideEventsPlan.join('\n'),
    );

    final payoutPlan = await explainQueryPlan(
      db,
      sql: 'SELECT id FROM payout_records WHERE escrow_id = ? LIMIT 1',
      args: const <Object?>['escrow_perf_1999'],
    );
    expect(queryPlanUsesIndex(payoutPlan), true, reason: payoutPlan.join('\n'));
  });
}

Future<void> _seedLargeDataset(Database db, DateTime now) async {
  await _seedUsers(db, now, userPairs: 250);
  await _seedRidesAndEvents(db, now, rideCount: 10000, userPairs: 250);
  await _seedWalletLedger(db, now, ledgerCount: 50000, userPairs: 250);
  await _seedEscrowsAndPayouts(db, now, payoutCount: 2000);
  await _seedPenaltyRecords(db, now, penaltyCount: 5000, userPairs: 250);
  await _seedPolicyRows(db, now);
}

Future<void> _seedUsers(
  Database db,
  DateTime now, {
  required int userPairs,
}) async {
  final nowIso = now.toIso8601String();
  final batch = db.batch();
  for (var i = 0; i < userPairs; i++) {
    batch.insert('users', <String, Object?>{
      'id': 'rider_perf_$i',
      'role': 'rider',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('users', <String, Object?>{
      'id': 'driver_perf_$i',
      'role': 'driver',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  batch.insert('users', <String, Object?>{
    'id': 'platform',
    'role': 'admin',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await batch.commit(noResult: true);
}

Future<void> _seedRidesAndEvents(
  Database db,
  DateTime now, {
  required int rideCount,
  required int userPairs,
}) async {
  final nowIso = now.toIso8601String();
  for (var chunkStart = 0; chunkStart < rideCount; chunkStart += 500) {
    final chunkEnd = (chunkStart + 500 < rideCount)
        ? chunkStart + 500
        : rideCount;
    final batch = db.batch();
    for (var i = chunkStart; i < chunkEnd; i++) {
      final rider = 'rider_perf_${i % userPairs}';
      final driver = 'driver_perf_${i % userPairs}';
      final rideId = 'ride_perf_$i';
      batch.insert('rides', <String, Object?>{
        'id': rideId,
        'rider_id': rider,
        'driver_id': driver,
        'trip_scope': 'intra_city',
        'status': 'completed',
        'bidding_mode': 1,
        'base_fare_minor': 10000,
        'premium_markup_minor': 500,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 10500,
        'connection_fee_minor': 0,
        'connection_fee_paid': 1,
        'pricing_version': 'pricing_seed',
        'pricing_breakdown_json': '{"seed":true}',
        'quoted_fare_minor': 10500,
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.insert('ride_events', <String, Object?>{
        'id': 'ride_event_perf_$i',
        'ride_id': rideId,
        'event_type': 'RIDE_COMPLETED',
        'actor_id': driver,
        'idempotency_scope': 'ride_event_perf',
        'idempotency_key': 'ride_event_perf_$i',
        'payload_json': '{}',
        'created_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

Future<void> _seedWalletLedger(
  Database db,
  DateTime now, {
  required int ledgerCount,
  required int userPairs,
}) async {
  for (var chunkStart = 0; chunkStart < ledgerCount; chunkStart += 1000) {
    final chunkEnd = (chunkStart + 1000 < ledgerCount)
        ? chunkStart + 1000
        : ledgerCount;
    final batch = db.batch();
    for (var i = chunkStart; i < chunkEnd; i++) {
      final ownerId = 'driver_perf_${i % userPairs}';
      final createdAt = now.add(Duration(seconds: i)).toIso8601String();
      batch.insert('wallet_ledger', <String, Object?>{
        'owner_id': ownerId,
        'wallet_type': 'driver_a',
        'direction': 'credit',
        'amount_minor': 1000,
        'balance_after_minor': (i + 1) * 1000,
        'kind': 'perf_seed_credit',
        'reference_id': 'ride_perf_${i % 10000}',
        'idempotency_scope': 'perf_wallet_ledger',
        'idempotency_key': 'perf_wallet_ledger_$i',
        'created_at': createdAt,
        'transfer_id': 'transfer_perf_${i % 2000}',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

Future<void> _seedEscrowsAndPayouts(
  Database db,
  DateTime now, {
  required int payoutCount,
}) async {
  for (var chunkStart = 0; chunkStart < payoutCount; chunkStart += 500) {
    final chunkEnd = (chunkStart + 500 < payoutCount)
        ? chunkStart + 500
        : payoutCount;
    final batch = db.batch();
    for (var i = chunkStart; i < chunkEnd; i++) {
      final rideId = 'ride_perf_$i';
      final rider = 'rider_perf_$i';
      final escrowId = 'escrow_perf_$i';
      final nowIso = now.add(Duration(minutes: i)).toIso8601String();
      batch.insert('escrow_holds', <String, Object?>{
        'id': escrowId,
        'ride_id': rideId,
        'holder_user_id': rider,
        'amount_minor': 10500,
        'status': 'released',
        'release_mode': 'manual_override',
        'created_at': nowIso,
        'released_at': nowIso,
        'idempotency_scope': 'perf_escrow',
        'idempotency_key': 'perf_escrow_$i',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.insert('payout_records', <String, Object?>{
        'id': 'payout_perf_$i',
        'ride_id': rideId,
        'escrow_id': escrowId,
        'trigger': 'manual_override',
        'status': 'completed',
        'recipient_owner_id': 'driver_perf_$i',
        'recipient_wallet_type': 'driver_a',
        'total_paid_minor': 8000,
        'commission_gross_minor': 8000,
        'commission_saved_minor': 0,
        'commission_remainder_minor': 8000,
        'premium_locked_minor': 0,
        'driver_allowance_minor': 0,
        'cash_debt_minor': 0,
        'penalty_due_minor': 0,
        'breakdown_json': '{}',
        'idempotency_scope': 'perf_payout',
        'idempotency_key': 'perf_payout_$i',
        'created_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

Future<void> _seedPenaltyRecords(
  Database db,
  DateTime now, {
  required int penaltyCount,
  required int userPairs,
}) async {
  for (var chunkStart = 0; chunkStart < penaltyCount; chunkStart += 1000) {
    final chunkEnd = (chunkStart + 1000 < penaltyCount)
        ? chunkStart + 1000
        : penaltyCount;
    final batch = db.batch();
    for (var i = chunkStart; i < chunkEnd; i++) {
      batch.insert('penalty_records', <String, Object?>{
        'id': 'penalty_perf_$i',
        'ride_id': 'ride_perf_${i % 10000}',
        'user_id': 'driver_perf_${i % userPairs}',
        'amount_minor': 500,
        'rule_code': 'perf_rule',
        'status': 'collected',
        'created_at': now.add(Duration(minutes: i)).toIso8601String(),
        'idempotency_scope': 'perf_penalty',
        'idempotency_key': 'perf_penalty_$i',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

Future<void> _seedPolicyRows(Database db, DateTime now) async {
  final pricingBatch = db.batch();
  for (var i = 0; i < 200; i++) {
    pricingBatch.insert('pricing_rules', <String, Object?>{
      'version': 'perf_pricing_$i',
      'effective_from': now.subtract(Duration(days: 200 - i)).toIso8601String(),
      'scope': 'default',
      'parameters_json': '{"base_fare_minor":{"intra_city":15000}}',
      'created_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  await pricingBatch.commit(noResult: true);

  final penaltyBatch = db.batch();
  for (var i = 0; i < 200; i++) {
    penaltyBatch.insert('penalty_rules', <String, Object?>{
      'version': 'perf_penalty_$i',
      'effective_from': now.subtract(Duration(days: 200 - i)).toIso8601String(),
      'scope': 'default',
      'parameters_json':
          '{"intra":{"late_fee_minor":50000,"late_if_cancelled_at_or_after_departure":true}}',
      'created_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  await penaltyBatch.commit(noResult: true);

  final complianceBatch = db.batch();
  complianceBatch.insert('compliance_requirements', <String, Object?>{
    'id': 'perf_compliance_ng_gh',
    'scope': 'international',
    'from_country': 'NG',
    'to_country': 'GH',
    'required_docs_json':
        '{"requires_next_of_kin":true,"allowed_doc_types":["passport"],"requires_verified":true,"requires_not_expired":true}',
    'created_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  for (var i = 0; i < 99; i++) {
    final from = 'C${i.toString().padLeft(2, '0')}';
    final to = 'D${i.toString().padLeft(2, '0')}';
    complianceBatch.insert('compliance_requirements', <String, Object?>{
      'id': 'perf_compliance_$i',
      'scope': 'international',
      'from_country': from,
      'to_country': to,
      'required_docs_json':
          '{"requires_next_of_kin":true,"allowed_doc_types":["passport"],"requires_verified":true,"requires_not_expired":true}',
      'created_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  await complianceBatch.commit(noResult: true);
}
