import 'dart:io';

import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DbProvider {
  DbProvider._();

  static final DbProvider instance = DbProvider._();

  Database? _database;

  Future<Database> open() async {
    if (_database != null) {
      return _database!;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = Platform.environment['DB_PATH']?.trim();
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
