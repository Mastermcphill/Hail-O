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

    final fakeDb = _SchemaAwareFakeMigrationDatabase();
    final migrator = BackendPostgresMigrator(
      migrationDatabase: fakeDb,
      migrationsDirectory: tempDir.path,
      dbSchema: 'hailo_prod',
    );

    await migrator.runPendingMigrations();
    expect(fakeDb.appliedMigrationsBySchema['hailo_prod'], <String>{
      '001_first.sql',
      '002_second.sql',
    });
    expect(fakeDb.executedMigrationStatements.length, 2);

    await migrator.runPendingMigrations();
    expect(fakeDb.appliedMigrationsBySchema['hailo_prod'], <String>{
      '001_first.sql',
      '002_second.sql',
    });
    expect(fakeDb.executedMigrationStatements.length, 2);
  });

  test('migrator scopes schema_migrations by DB schema', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'hailo_migrator_schema_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final migrationOne = File('${tempDir.path}/001_first.sql');
    await migrationOne.writeAsString(
      'CREATE TABLE IF NOT EXISTS one (id INT);',
    );

    final fakeDb = _SchemaAwareFakeMigrationDatabase();
    final prodMigrator = BackendPostgresMigrator(
      migrationDatabase: fakeDb,
      migrationsDirectory: tempDir.path,
      dbSchema: 'hailo_prod',
    );
    final stagingMigrator = BackendPostgresMigrator(
      migrationDatabase: fakeDb,
      migrationsDirectory: tempDir.path,
      dbSchema: 'hailo_staging',
    );

    await prodMigrator.runPendingMigrations();
    await stagingMigrator.runPendingMigrations();

    expect(fakeDb.appliedMigrationsBySchema['hailo_prod'], <String>{
      '001_first.sql',
    });
    expect(fakeDb.appliedMigrationsBySchema['hailo_staging'], <String>{
      '001_first.sql',
    });
    expect(
      fakeDb.allStatements.any(
        (statement) =>
            statement.contains('CREATE SCHEMA IF NOT EXISTS "hailo_prod"'),
      ),
      isTrue,
    );
    expect(
      fakeDb.allStatements.any(
        (statement) =>
            statement.contains('CREATE SCHEMA IF NOT EXISTS "hailo_staging"'),
      ),
      isTrue,
    );
    expect(
      fakeDb.allStatements.where(
        (statement) => statement.contains('public.schema_migrations'),
      ),
      isEmpty,
    );
  });
}

class _SchemaAwareFakeMigrationDatabase implements MigrationDatabase {
  final Map<String, Set<int>> appliedVersionsBySchema = <String, Set<int>>{};
  final Map<String, Set<String>> appliedMigrationsBySchema =
      <String, Set<String>>{};
  final List<String> executedMigrationStatements = <String>[];
  final List<String> allStatements = <String>[];

  @override
  Future<void> execute(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) async {
    final trimmed = statement.trim();
    allStatements.add(trimmed);
    if (trimmed.contains('INSERT INTO') &&
        trimmed.contains('schema_migrations')) {
      final schema = _schemaFromStatement(trimmed);
      final version = substitutionValues['version'] as int;
      final name = substitutionValues['name'] as String;
      appliedVersionsBySchema.putIfAbsent(schema, () => <int>{}).add(version);
      appliedMigrationsBySchema.putIfAbsent(schema, () => <String>{}).add(name);
      return;
    }
    if (trimmed.contains('schema_migrations') ||
        trimmed.startsWith('CREATE SCHEMA IF NOT EXISTS')) {
      return;
    }
    executedMigrationStatements.add(trimmed);
  }

  @override
  Future<List<List<Object?>>> query(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) async {
    final trimmed = statement.trim();
    allStatements.add(trimmed);
    if (trimmed.contains('SELECT 1 FROM') &&
        trimmed.contains('schema_migrations')) {
      final schema = _schemaFromStatement(trimmed);
      final version = substitutionValues['version'] as int;
      final applied = appliedVersionsBySchema[schema] ?? <int>{};
      if (applied.contains(version)) {
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

  String _schemaFromStatement(String statement) {
    final match = RegExp(r'"([^"]+)"\.schema_migrations').firstMatch(statement);
    return match?.group(1) ?? 'unknown';
  }
}
