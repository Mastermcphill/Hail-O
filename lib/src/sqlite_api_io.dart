import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

export 'package:sqflite_common/sqlite_api.dart';
export 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

const String inMemoryDatabasePath = ':memory:';

Future<Database> openDatabase(
  String path, {
  int? version,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseCreateFn? onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
  OnDatabaseVersionChangeFn? onDowngrade,
  OnDatabaseOpenFn? onOpen,
  bool? readOnly = false,
  bool? singleInstance = true,
}) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onDowngrade: onDowngrade,
      onOpen: onOpen,
      readOnly: readOnly,
      singleInstance: singleInstance,
    ),
  );
}

Future<String> getDatabasesPath() async {
  final directory = Directory(p.join(Directory.current.path, '.db'));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory.path;
}

Future<void> deleteDatabase(String path) {
  return databaseFactory.deleteDatabase(path);
}
