import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import 'postgres_provider.dart';
import 'runtime_config.dart';

typedef SqliteDatabaseOpener = Future<Database> Function(String? databasePath);
typedef PostgresProviderFactory =
    PostgresProvider Function(
      String databaseUrl, {
      int poolSize,
      String dbSchema,
      int statementTimeoutMs,
    });

class DbHandle {
  const DbHandle._({
    required this.dbMode,
    this.sqliteDatabase,
    this.postgresProvider,
  });

  final BackendDbMode dbMode;
  final Database? sqliteDatabase;
  final PostgresProvider? postgresProvider;
}

class DbProvider {
  DbProvider._({
    SqliteDatabaseOpener? sqliteOpener,
    PostgresProviderFactory? postgresProviderFactory,
    void Function(String message)? logger,
  }) : _sqliteOpener = sqliteOpener ?? _defaultSqliteOpen,
       _postgresProviderFactory =
           postgresProviderFactory ?? _defaultPostgresProviderFactory,
       _logger = logger ?? _defaultLogger;

  factory DbProvider.forTesting({
    required SqliteDatabaseOpener sqliteOpener,
    PostgresProviderFactory? postgresProviderFactory,
    void Function(String message)? logger,
  }) {
    return DbProvider._(
      sqliteOpener: sqliteOpener,
      postgresProviderFactory: postgresProviderFactory,
      logger: logger,
    );
  }

  static final DbProvider instance = DbProvider._();

  final SqliteDatabaseOpener _sqliteOpener;
  final PostgresProviderFactory _postgresProviderFactory;
  final void Function(String message) _logger;
  Database? _sqliteDatabase;
  PostgresProvider? _postgresProvider;

  Future<DbHandle> open({
    String? databasePath,
    BackendDbMode dbMode = BackendDbMode.sqlite,
    String? databaseUrl,
    String dbSchema = 'public',
    int poolSize = 4,
    int statementTimeoutMs = 10000,
  }) async {
    if (dbMode == BackendDbMode.postgres) {
      final resolvedDatabaseUrl =
          (databaseUrl ?? Platform.environment['DATABASE_URL'] ?? '').trim();
      if (resolvedDatabaseUrl.isEmpty) {
        throw StateError(
          'BACKEND_DB_MODE=postgres requires DATABASE_URL environment variable',
        );
      }
      final cachedPostgresProvider = _postgresProvider;
      if (cachedPostgresProvider != null) {
        return DbHandle._(
          dbMode: BackendDbMode.postgres,
          postgresProvider: cachedPostgresProvider,
        );
      }
      final postgresProvider = _postgresProviderFactory(
        resolvedDatabaseUrl,
        poolSize: poolSize,
        dbSchema: dbSchema,
        statementTimeoutMs: statementTimeoutMs,
      );
      _postgresProvider = postgresProvider;
      _logger('db_mode=postgres: initialized postgres provider');
      return DbHandle._(
        dbMode: BackendDbMode.postgres,
        postgresProvider: postgresProvider,
      );
    }

    if (_sqliteDatabase != null) {
      return DbHandle._(
        dbMode: BackendDbMode.sqlite,
        sqliteDatabase: _sqliteDatabase!,
      );
    }

    final dbPath = databasePath ?? Platform.environment['DB_PATH']?.trim();
    _sqliteDatabase = await _sqliteOpener(
      (dbPath == null || dbPath.isEmpty) ? null : dbPath,
    );
    return DbHandle._(
      dbMode: BackendDbMode.sqlite,
      sqliteDatabase: _sqliteDatabase!,
    );
  }

  Future<void> close() async {
    final sqliteDatabase = _sqliteDatabase;
    _sqliteDatabase = null;
    if (sqliteDatabase != null) {
      await sqliteDatabase.close();
    }

    final postgresProvider = _postgresProvider;
    _postgresProvider = null;
    if (postgresProvider != null) {
      await postgresProvider.close();
    }
  }

  static Future<Database> _defaultSqliteOpen(String? databasePath) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    return HailODatabase().open(databasePath: databasePath);
  }

  static PostgresProvider _defaultPostgresProviderFactory(
    String databaseUrl, {
    int poolSize = 4,
    String dbSchema = 'public',
    int statementTimeoutMs = 10000,
  }) {
    return PostgresProvider(
      databaseUrl,
      poolSize: poolSize,
      dbSchema: dbSchema,
      statementTimeoutMs: statementTimeoutMs,
    );
  }

  static void _defaultLogger(String message) {
    stdout.writeln(message);
  }
}
