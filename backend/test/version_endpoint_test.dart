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

  test('/version returns build metadata', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{
        'version': '1.2.3',
        'commit': 'abc1234',
      },
    );

    final response = await _request(handler, '/version');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], true);
    expect(body['version'], '1.2.3');
    expect(body['commit'], 'abc1234');
  });

  test('/health returns quickly when dependency health check stalls', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return true;
      },
      buildInfo: const <String, Object?>{'commit': 'slow-health-test'},
    );

    final stopwatch = Stopwatch()..start();
    final response = await _request(handler, '/health');
    stopwatch.stop();

    expect(response.statusCode, 503);
    expect(stopwatch.elapsedMilliseconds, lessThan(1200));
    final body = await _decodeBody(response);
    expect(body['ok'], false);
    expect(body['db_ok'], false);
  });
}

Handler _buildHandler({
  required Database db,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
}) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'sqlite',
    environment: 'test',
    requestMetrics: RequestMetrics(),
    dbHealthCheck: dbHealthCheck,
    buildInfo: buildInfo,
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
  ).buildHandler();
}

Future<Response> _request(Handler handler, String path) async {
  return handler(
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
