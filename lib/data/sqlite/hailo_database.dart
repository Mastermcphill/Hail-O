import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migration.dart';
import 'migration_runner.dart';
import 'migrations/m0001_initial_schema.dart';
import 'migrations/m0002_task2_task3_finance_logistics.dart';
import 'migrations/m0003_mapbox_offline_foundation.dart';
import 'migrations/m0004_fleet_configs.dart';

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
