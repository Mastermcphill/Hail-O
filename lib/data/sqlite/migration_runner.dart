import 'package:sqflite/sqflite.dart';

import 'migration.dart';
import 'table_names.dart';

class MigrationRunner {
  const MigrationRunner(this.migrations);

  final List<Migration> migrations;

  Future<void> run(Database db) async {
    await _ensureMigrationsTable(db);

    final applied = await db.query(
      TableNames.schemaMigrations,
      columns: <String>['version', 'checksum'],
    );

    final appliedMap = <int, String>{
      for (final row in applied)
        (row['version'] as int): (row['checksum'] as String? ?? ''),
    };

    final orderedMigrations = List<Migration>.from(migrations)
      ..sort((a, b) => a.version.compareTo(b.version));

    for (final migration in orderedMigrations) {
      final existingChecksum = appliedMap[migration.version];
      if (existingChecksum != null) {
        if (existingChecksum != migration.checksum) {
          throw StateError(
            'Migration checksum mismatch for version ${migration.version}: '
            'expected ${migration.checksum}, found $existingChecksum',
          );
        }
        continue;
      }

      await db.transaction((txn) async {
        for (final statement in migration.upSql) {
          await txn.execute(statement);
        }
        await txn.insert(TableNames.schemaMigrations, <String, Object?>{
          'version': migration.version,
          'name': migration.name,
          'checksum': migration.checksum,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      });
    }
  }

  Future<void> _ensureMigrationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.schemaMigrations} (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        checksum TEXT NOT NULL,
        applied_at TEXT NOT NULL
      )
    ''');
  }
}
