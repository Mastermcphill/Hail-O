import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

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

  test('invalid JSON response includes trace_id', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(db);
    final response = await handler(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        headers: const <String, String>{
          'content-type': 'application/json',
          'idempotency-key': 'bad-json-1',
        },
        body: '{',
      ),
    );

    expect(response.statusCode, 400);
    final decoded =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(decoded['code'], 'invalid_format');
    expect((decoded['trace_id'] as String?)?.isNotEmpty, isTrue);
  });

  test('/metrics is protected by default', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(db);
    final response = await handler(
      shelf.Request('GET', Uri.parse('http://localhost/metrics')),
    );

    expect(response.statusCode, 401);
    final decoded =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(decoded['code'], 'unauthorized');
  });
}

Handler _buildHandler(Database db) {
  return AppServer(
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
  ).buildHandler();
}
