import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

export 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _bootstrapped = false;
String? _cachedSkipReason;

const String _windowsMissingDllSkipReason =
    'Skipping DB tests: sqlite3.dll not found. Install sqlite-tools and add sqlite3.dll to PATH.';

String? bootstrapSqliteFfiForTests() {
  if (_bootstrapped) {
    return null;
  }
  if (_cachedSkipReason != null) {
    return _cachedSkipReason;
  }

  final originalDirectory = Directory.current.path;
  final bootstrapDirectory = _resolveWindowsBootstrapDirectory();

  try {
    if (bootstrapDirectory != null) {
      Directory.current = bootstrapDirectory;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _bootstrapped = true;
    return null;
  } catch (error) {
    if (Platform.isWindows && _looksLikeMissingSqliteDll(error)) {
      _cachedSkipReason = _windowsMissingDllSkipReason;
      return _cachedSkipReason;
    }
    rethrow;
  } finally {
    if (Directory.current.path != originalDirectory) {
      Directory.current = originalDirectory;
    }
  }
}

String? _resolveWindowsBootstrapDirectory() {
  if (!Platform.isWindows) {
    return null;
  }

  final currentDll = File(path.join(Directory.current.path, 'sqlite3.dll'));
  if (currentDll.existsSync()) {
    return null;
  }

  final bundledDll = File(
    path.join(Directory.current.path, 'backend', 'sqlite3.dll'),
  );
  if (bundledDll.existsSync()) {
    return bundledDll.parent.path;
  }

  return null;
}

bool _looksLikeMissingSqliteDll(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('sqlite3.dll') ||
      (message.contains('sqlite3') &&
          message.contains('module could not be found')) ||
      (message.contains('sqlite3') &&
          message.contains('specified module could not be found'));
}
