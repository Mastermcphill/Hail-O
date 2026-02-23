import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import 'runtime_config.dart';

typedef SqliteDatabaseOpener = Future<Database> Function(String? databasePath);

class DbProvider {
  DbProvider._({
    SqliteDatabaseOpener? sqliteOpener,
    void Function(String message)? logger,
  }) : _sqliteOpener = sqliteOpener ?? _defaultSqliteOpen,
       _logger = logger ?? _defaultLogger;

  factory DbProvider.forTesting({
    required SqliteDatabaseOpener sqliteOpener,
    void Function(String message)? logger,
  }) {
    return DbProvider._(sqliteOpener: sqliteOpener, logger: logger);
  }

  static final DbProvider instance = DbProvider._();

  final SqliteDatabaseOpener _sqliteOpener;
  final void Function(String message) _logger;
  Database? _database;

  Future<Database> open({
    String? databasePath,
    BackendDbMode dbMode = BackendDbMode.sqlite,
  }) async {
    if (dbMode == BackendDbMode.postgres) {
      _logger('db_mode=postgres: skipping sqlite initialization');
      return const _PostgresBypassDatabase();
    }

    if (_database != null) {
      return _database!;
    }

    final dbPath = databasePath ?? Platform.environment['DB_PATH']?.trim();
    _database = await _sqliteOpener(
      (dbPath == null || dbPath.isEmpty) ? null : dbPath,
    );
    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  static Future<Database> _defaultSqliteOpen(String? databasePath) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    return HailODatabase().open(databasePath: databasePath);
  }

  static void _defaultLogger(String message) {
    stdout.writeln(message);
  }
}

class _PostgresBypassDatabase implements Database {
  const _PostgresBypassDatabase();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'SQLite APIs are unavailable when BACKEND_DB_MODE=postgres.',
    );
  }
}
