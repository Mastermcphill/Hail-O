import 'package:hail_o_finance_core/data/sqlite/migration.dart';
import 'package:hail_o_finance_core/data/sqlite/migration_runner.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0001_initial_schema.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0002_task2_task3_finance_logistics.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0003_mapbox_offline_foundation.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0004_fleet_configs.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0005_ride_settlement_payout_records.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0006_penalty_records.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0007_reversal_and_payout_guards.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0008_ride_events_orchestrator.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0009_ledger_indexes_and_invariants.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0010_pricing_snapshot_on_rides.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0011_disputes_workflow.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0012_documents_compliance_fields.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0013_orchestrator_mutation_events.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0014_wallet_transfer_journal.dart';
import 'package:hail_o_finance_core/data/sqlite/migrations/m0015_policy_rules_tables.dart';
import 'package:sqflite/sqflite.dart';

List<Migration> allMigrations() {
  return const <Migration>[
    M0001InitialSchema(),
    M0002Task2Task3FinanceLogistics(),
    M0003MapboxOfflineFoundation(),
    M0004FleetConfigs(),
    M0005RideSettlementPayoutRecords(),
    M0006PenaltyRecords(),
    M0007ReversalAndPayoutGuards(),
    M0008RideEventsOrchestrator(),
    M0009LedgerIndexesAndInvariants(),
    M0010PricingSnapshotOnRides(),
    M0011DisputesWorkflow(),
    M0012DocumentsComplianceFields(),
    M0013OrchestratorMutationEvents(),
    M0014WalletTransferJournal(),
    M0015PolicyRulesTables(),
  ];
}

Future<Database> openDatabaseAtVersion({required int maxVersion}) async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    onConfigure: (Database database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
  );
  final subset = allMigrations()
      .where((migration) => migration.version <= maxVersion)
      .toList(growable: false);
  await MigrationRunner(subset).run(db);
  return db;
}

Future<void> upgradeDatabaseToHead(Database db) async {
  await MigrationRunner(allMigrations()).run(db);
}

Future<void> seedLegacyRideState({
  required Database db,
  required DateTime nowUtc,
  required String rideId,
  required String escrowId,
  required String riderId,
  required String driverId,
  required bool includePenaltyRecord,
  required bool includeLegacyPenalty,
}) async {
  final nowIso = nowUtc.toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': riderId,
    'role': 'rider',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': driverId,
    'role': 'driver',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('rides', <String, Object?>{
    'id': rideId,
    'rider_id': riderId,
    'driver_id': driverId,
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
    'pricing_version': 'legacy_v0',
    'pricing_breakdown_json': '{"source":"legacy_seed"}',
    'quoted_fare_minor': 10000,
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('escrow_holds', <String, Object?>{
    'id': escrowId,
    'ride_id': rideId,
    'holder_user_id': riderId,
    'amount_minor': 10000,
    'status': 'released',
    'release_mode': 'manual_override',
    'created_at': nowIso,
    'released_at': nowIso,
    'idempotency_scope': 'seed_escrow',
    'idempotency_key': 'seed_escrow:$escrowId',
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  if (includeLegacyPenalty) {
    await db.insert('penalties', <String, Object?>{
      'id': 'legacy:$rideId',
      'user_id': driverId,
      'penalty_kind': 'legacy_seed_penalty',
      'amount_minor': 9000,
      'reason': rideId,
      'created_at': nowIso,
      'idempotency_scope': 'legacy_seed_penalty',
      'idempotency_key': 'legacy_seed_penalty:$rideId',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  if (includePenaltyRecord) {
    await db.insert('penalty_records', <String, Object?>{
      'id': 'record:$rideId',
      'ride_id': rideId,
      'user_id': driverId,
      'amount_minor': 2500,
      'rule_code': 'seed_penalty_record',
      'status': 'assessed',
      'created_at': nowIso,
      'idempotency_scope': 'cancellation_penalty',
      'idempotency_key': 'seed_penalty_record:$rideId',
      'ride_type': 'intra',
      'total_fare_minor': 10000,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
