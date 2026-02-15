import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;

import 'infra/db_provider.dart';
import 'infra/token_service.dart';
import 'server/app_server.dart';

Future<void> main() async {
  final db = await DbProvider.instance.open();
  final tokenService = TokenService.fromEnvironment();
  final handler = AppServer(db: db, tokenService: tokenService).buildHandler();

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Hail-O backend listening on http://${server.address.host}:${server.port}',
  );
}
