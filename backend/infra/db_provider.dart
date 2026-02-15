import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/data/sqlite/hailo_database.dart';

class DbProvider {
  DbProvider._();

  static final DbProvider instance = DbProvider._();

  Database? _database;

  Future<Database> open({String? databasePath}) async {
    if (_database != null) {
      return _database!;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = databasePath ?? Platform.environment['DB_PATH']?.trim();
    _database = await HailODatabase().open(
      databasePath: (dbPath == null || dbPath.isEmpty) ? null : dbPath,
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
}
