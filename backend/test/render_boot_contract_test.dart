import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/sqlite_auth_credentials_store.dart';
import '../modules/rides/sqlite_operational_record_store.dart';
import '../modules/rides/sqlite_ride_request_metadata_store.dart';
import '../server/app_server.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('healthz alias and /api/healthz are public and return 200', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = AppServer(
      db: db,
      tokenService: TokenService(secret: 'backend-test-secret'),
      dbMode: 'sqlite',
      environment: 'test',
      requestMetrics: RequestMetrics(),
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
      authCredentialsStore: SqliteAuthCredentialsStore(db),
      rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
      operationalRecordStore: const SqliteOperationalRecordStore(),
      environmentMap: const <String, String>{},
    ).buildHandler();

    final healthz = await _request(handler, '/healthz');
    final apiHealthz = await _request(handler, '/api/healthz');

    expect(healthz.statusCode, 200);
    expect(apiHealthz.statusCode, 200);

    final healthzBody = await _decodeBody(healthz);
    final apiHealthzBody = await _decodeBody(apiHealthz);
    expect(healthzBody['ok'], true);
    expect(apiHealthzBody['ok'], true);
    expect(healthzBody['service'], 'hail-o-backend');
    expect(apiHealthzBody['service'], 'hail-o-backend');
  });
}

Future<Response> _request(Handler handler, String path) async {
  return await handler(
    shelf.Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: const <String, String>{'accept': 'application/json'},
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
