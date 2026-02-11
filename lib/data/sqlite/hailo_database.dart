import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migration.dart';
import 'migration_runner.dart';
import 'migrations/m0001_initial_schema.dart';
import 'migrations/m0002_task2_task3_finance_logistics.dart';
import 'migrations/m0003_mapbox_offline_foundation.dart';
import 'migrations/m0004_fleet_configs.dart';
import 'migrations/m0005_ride_settlement_payout_records.dart';
import 'migrations/m0006_penalty_records.dart';
import 'migrations/m0007_reversal_and_payout_guards.dart';
import 'migrations/m0008_ride_events_orchestrator.dart';
import 'migrations/m0009_ledger_indexes_and_invariants.dart';
import 'migrations/m0010_pricing_snapshot_on_rides.dart';
import 'migrations/m0011_disputes_workflow.dart';
import 'migrations/m0012_documents_compliance_fields.dart';
import 'migrations/m0013_orchestrator_mutation_events.dart';
import 'migrations/m0014_wallet_transfer_journal.dart';
import 'migrations/m0015_policy_rules_tables.dart';

class HailODatabase {
  HailODatabase({
    this.databaseName = 'hail_o_backend_core.db',
    List<Migration>? migrations,
  }) : _migrations =
           migrations ??
           const <Migration>[
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

  final String databaseName;
  final List<Migration> _migrations;

  Future<Database> open({String? databasePath}) async {
    final path = databasePath ?? p.join(await getDatabasesPath(), databaseName);
    final db = await openDatabase(
      path,
      version: _migrations.isEmpty ? 1 : _migrations.last.version,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    final runner = MigrationRunner(_migrations);
    await runner.run(db);
    return db;
  }

  Future<Database> openInMemory() {
    return open(databasePath: inMemoryDatabasePath);
  }
}
