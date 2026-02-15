import 'dart:io';

import 'package:postgres/postgres.dart';

import 'postgres_provider.dart';

class BackendPostgresMigrator {
  BackendPostgresMigrator({
    required PostgresProvider postgresProvider,
    String? migrationsDirectory,
  }) : _postgresProvider = postgresProvider,
       migrationsDirectory =
           migrationsDirectory ?? _resolveMigrationsDirectory();

  final PostgresProvider _postgresProvider;
  final String migrationsDirectory;

  Future<void> runPendingMigrations() async {
    final connection = await _postgresProvider.open();
    await _ensureMigrationsTable(connection);

    final directory = Directory(migrationsDirectory);
    if (!await directory.exists()) {
      return;
    }

    final entries = await directory
        .list()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.sql'),
        )
        .cast<File>()
        .toList();
    entries.sort(
      (a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
    );

    for (final file in entries) {
      final name = file.uri.pathSegments.last;
      final alreadyApplied = await _isApplied(connection, name);
      if (alreadyApplied) {
        continue;
      }
      final sql = await file.readAsString();
      await connection.transaction((ctx) async {
        for (final statement in _splitStatements(sql)) {
          await ctx.execute(statement);
        }
        await ctx.execute(
          '''
          INSERT INTO schema_migrations(name, applied_at)
          VALUES (@name, NOW())
          ''',
          substitutionValues: <String, Object?>{'name': name},
        );
      });
    }
  }

  Future<void> _ensureMigrationsTable(PostgreSQLConnection connection) async {
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
  }

  Future<bool> _isApplied(PostgreSQLConnection connection, String name) async {
    final result = await connection.query(
      'SELECT 1 FROM schema_migrations WHERE name = @name LIMIT 1',
      substitutionValues: <String, Object?>{'name': name},
    );
    return result.isNotEmpty;
  }

  Iterable<String> _splitStatements(String sql) sync* {
    for (final raw in sql.split(';')) {
      final statement = raw.trim();
      if (statement.isNotEmpty) {
        yield statement;
      }
    }
  }

  static String _resolveMigrationsDirectory() {
    const candidates = <String>['backend/migrations', 'migrations'];
    for (final candidate in candidates) {
      if (Directory(candidate).existsSync()) {
        return candidate;
      }
    }
    return 'backend/migrations';
  }
}
