import 'dart:io';

import 'package:postgres/postgres.dart';

import 'postgres_provider.dart';

abstract class MigrationDatabase {
  Future<void> execute(
    String statement, {
    Map<String, Object?> substitutionValues,
  });

  Future<List<List<Object?>>> query(
    String statement, {
    Map<String, Object?> substitutionValues,
  });

  Future<T> transaction<T>(Future<T> Function(MigrationDatabase txn) action);
}

class ProviderMigrationDatabase implements MigrationDatabase {
  ProviderMigrationDatabase(this._provider);

  final PostgresProvider _provider;

  @override
  Future<void> execute(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) {
    return _provider.withConnection((connection) {
      return connection.execute(
        statement,
        substitutionValues: substitutionValues,
      );
    });
  }

  @override
  Future<List<List<Object?>>> query(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) {
    return _provider.withConnection((connection) {
      return connection.query(
        statement,
        substitutionValues: substitutionValues,
      );
    });
  }

  @override
  Future<T> transaction<T>(Future<T> Function(MigrationDatabase txn) action) {
    return _provider.withTxn((ctx) {
      return action(_ExecutionContextMigrationDatabase(ctx));
    });
  }
}

class _ExecutionContextMigrationDatabase implements MigrationDatabase {
  const _ExecutionContextMigrationDatabase(this._ctx);

  final PostgreSQLExecutionContext _ctx;

  @override
  Future<void> execute(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) {
    return _ctx.execute(statement, substitutionValues: substitutionValues);
  }

  @override
  Future<List<List<Object?>>> query(
    String statement, {
    Map<String, Object?> substitutionValues = const <String, Object?>{},
  }) {
    return _ctx.query(statement, substitutionValues: substitutionValues);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(MigrationDatabase txn) action) {
    return action(this);
  }
}

class BackendPostgresMigrator {
  BackendPostgresMigrator({
    PostgresProvider? postgresProvider,
    MigrationDatabase? migrationDatabase,
    String? migrationsDirectory,
  }) : assert(postgresProvider != null || migrationDatabase != null),
       _migrationDatabase =
           migrationDatabase ?? ProviderMigrationDatabase(postgresProvider!),
       migrationsDirectory =
           migrationsDirectory ?? _resolveMigrationsDirectory();

  final MigrationDatabase _migrationDatabase;
  final String migrationsDirectory;

  Future<void> runPendingMigrations() async {
    await _ensureMigrationsTable(_migrationDatabase);

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
      final version = _versionFromMigrationName(name);
      final alreadyApplied = await _isApplied(_migrationDatabase, version);
      if (alreadyApplied) {
        continue;
      }
      final sql = await file.readAsString();
      await _migrationDatabase.transaction((txn) async {
        for (final statement in _splitStatements(sql)) {
          await txn.execute(statement);
        }
        await txn.execute(
          '''
          INSERT INTO schema_migrations(version, name, applied_at)
          VALUES (@version, @name, NOW())
          ''',
          substitutionValues: <String, Object?>{
            'version': version,
            'name': name,
          },
        );
      });
    }
  }

  Future<void> _ensureMigrationsTable(MigrationDatabase database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await database.execute(
      'ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS version INTEGER',
    );
    await database.execute(
      'ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS name TEXT',
    );
    await database.execute(
      'ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
    );
  }

  Future<bool> _isApplied(MigrationDatabase database, int version) async {
    final result = await database.query(
      'SELECT 1 FROM schema_migrations WHERE version = @version LIMIT 1',
      substitutionValues: <String, Object?>{'version': version},
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

  int _versionFromMigrationName(String migrationName) {
    final prefix = migrationName.split('_').first;
    final parsed = int.tryParse(prefix);
    if (parsed == null) {
      throw FormatException(
        'Migration filename must start with a numeric version prefix: $migrationName',
      );
    }
    return parsed;
  }
}
