import 'dart:io';

import 'package:test/test.dart';

import '../infra/migrator.dart';

void main() {
  test('migrator applies each SQL file once and tracks versions', () async {
    final tempDir = await Directory.systemTemp.createTemp('hailo_migrator_');
    addTearDown(() => tempDir.delete(recursive: true));

    final migrationOne = File('${tempDir.path}/001_first.sql');
    await migrationOne.writeAsString(
      'CREATE TABLE IF NOT EXISTS one (id INT);',
    );

    final migrationTwo = File('${tempDir.path}/002_second.sql');
    await migrationTwo.writeAsString(
      'CREATE TABLE IF NOT EXISTS two (id INT);',
    );

    final fakeDb = _FakeMigrationDatabase();
    final migrator = BackendPostgresMigrator(
      migrationDatabase: fakeDb,
      migrationsDirectory: tempDir.path,
    );

    await migrator.runPendingMigrations();
    expect(fakeDb.appliedMigrations, <String>{
      '001_first.sql',
      '002_second.sql',
    });
    expect(fakeDb.executedMigrationStatements.length, 2);

    await migrator.runPendingMigrations();
    expect(fakeDb.appliedMigrations, <String>{
      '001_first.sql',
      '002_second.sql',
    });
    expect(fakeDb.executedMigrationStatements.length, 2);
  });
}

class _FakeMigrationDatabase implements MigrationDatabase {
  final Set<String> appliedMigrations = <String>{};
  final List<String> executedMigrationStatements = <String>[];

  @override
  Future<void> execute(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) async {
    if (statement.contains('INSERT INTO schema_migrations')) {
      final name = substitutionValues['name'] as String;
      appliedMigrations.add(name);
      return;
    }
    if (statement.contains('CREATE TABLE IF NOT EXISTS schema_migrations')) {
      return;
    }
    executedMigrationStatements.add(statement.trim());
  }

  @override
  Future<List<List<Object?>>> query(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) async {
    if (statement.contains('SELECT 1 FROM schema_migrations')) {
      final name = substitutionValues['name'] as String;
      if (appliedMigrations.contains(name)) {
        return <List<Object?>>[
          <Object?>[1],
        ];
      }
      return <List<Object?>>[];
    }
    return <List<Object?>>[];
  }

  @override
  Future<T> transaction<T>(Future<T> Function(MigrationDatabase txn) action) {
    return action(this);
  }
}
