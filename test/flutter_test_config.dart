import 'dart:async';
import 'dart:io';

import 'support/sqlite_ffi_bootstrap.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final skipReason = bootstrapSqliteFfiForTests();
  if (skipReason != null && Platform.isWindows) {
    stderr.writeln(skipReason);
  }
  await testMain();
}
