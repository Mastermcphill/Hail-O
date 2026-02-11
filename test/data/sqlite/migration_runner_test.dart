import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/data/sqlite/table_names.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh DB applies migration and reopen does not duplicate', () async {
    final directory = await Directory.systemTemp.createTemp('hailo_migration_');
    final dbPath = p.join(directory.path, 'migration_runner_test.db');
    addTearDown(() async {
      await databaseFactory.deleteDatabase(dbPath);
      await directory.delete(recursive: true);
    });

    final database = HailODatabase();

    final first = await database.open(databasePath: dbPath);
    final firstRows = await first.query(TableNames.schemaMigrations);
    expect(firstRows.length, 4);
    final firstByVersion = <int, Map<String, Object?>>{
      for (final row in firstRows)
        (row['version'] as int): Map<String, Object?>.from(row),
    };
    expect(firstByVersion[1]?['checksum'], 'm0001_initial_schema_v1');
    expect(
      firstByVersion[2]?['checksum'],
      'm0002_task2_task3_finance_logistics_v1',
    );
    expect(
      firstByVersion[3]?['checksum'],
      'm0003_mapbox_offline_foundation_v1',
    );
    expect(firstByVersion[4]?['checksum'], 'm0004_fleet_configs_v1');
    await first.close();

    final second = await database.open(databasePath: dbPath);
    final secondRows = await second.query(TableNames.schemaMigrations);
    expect(secondRows.length, 4);
    await second.close();
  });
}
