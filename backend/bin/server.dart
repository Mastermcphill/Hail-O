import 'dart:io';

import '../main.dart' as backend_app;

Future<void> main() async {
  try {
    await backend_app.main();
  } catch (error, stackTrace) {
    stderr.writeln('FATAL: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
    rethrow;
  }
}
