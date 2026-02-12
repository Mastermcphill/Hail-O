import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/data/sqlite/table_names.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh DB applies migration and reopen does not duplicate', () async {
    final directory = await Directory.systemTemp.createTemp('hailo_migration_');
    final dbPath = p.join(directory.path, 'migration_runner_test.db');
    addTearDown(() async {
      await databaseFactory.deleteDatabase(dbPath);
      await directory.delete(recursive: true);
    });

    final database = HailODatabase();

    final first = await database.open(databasePath: dbPath);
    final firstRows = await first.query(TableNames.schemaMigrations);
    expect(firstRows.length, 17);
    final firstByVersion = <int, Map<String, Object?>>{
      for (final row in firstRows)
        (row['version'] as int): Map<String, Object?>.from(row),
    };
    expect(firstByVersion[1]?['checksum'], 'm0001_initial_schema_v1');
    expect(
      firstByVersion[2]?['checksum'],
      'm0002_task2_task3_finance_logistics_v1',
    );
    expect(
      firstByVersion[3]?['checksum'],
      'm0003_mapbox_offline_foundation_v1',
    );
    expect(firstByVersion[4]?['checksum'], 'm0004_fleet_configs_v1');
    expect(
      firstByVersion[5]?['checksum'],
      'm0005_ride_settlement_payout_records_v2',
    );
    expect(firstByVersion[6]?['checksum'], 'm0006_penalty_records_v2');
    expect(
      firstByVersion[7]?['checksum'],
      'm0007_reversal_and_payout_guards_v1',
    );
    expect(firstByVersion[8]?['checksum'], 'm0008_ride_events_orchestrator_v1');
    expect(
      firstByVersion[9]?['checksum'],
      'm0009_ledger_indexes_and_invariants_v1',
    );
    expect(
      firstByVersion[10]?['checksum'],
      'm0010_pricing_snapshot_on_rides_v1',
    );
    expect(firstByVersion[11]?['checksum'], 'm0011_disputes_workflow_v1');
    expect(
      firstByVersion[12]?['checksum'],
      'm0012_documents_compliance_fields_v1',
    );
    expect(
      firstByVersion[13]?['checksum'],
      'm0013_orchestrator_mutation_events_v1',
    );
    expect(firstByVersion[14]?['checksum'], 'm0014_wallet_transfer_journal_v1');
    expect(firstByVersion[15]?['checksum'], 'm0015_policy_rules_tables_v1');
    expect(firstByVersion[16]?['checksum'], 'm0016_operation_journal_v1');
    expect(firstByVersion[17]?['checksum'], 'm0017_rule_rollouts_v1');
    await first.close();

    final second = await database.open(databasePath: dbPath);
    final secondRows = await second.query(TableNames.schemaMigrations);
    expect(secondRows.length, 17);
    await second.close();
  });
}
