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

  test('register/login works and idempotency key is enforced', () async {
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
    ).buildHandler();

    final missingIdempotency = await _postJson(
      handler,
      '/auth/register',
      body: <String, Object?>{
        'email': 'backend.test@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
    );
    expect(missingIdempotency.statusCode, 400);
    final missingBody = await _decodeBody(missingIdempotency);
    expect(missingBody['code'], 'missing_idempotency_key');

    final register = await _postJson(
      handler,
      '/auth/register',
      idempotencyKey: 'backend-register-1',
      body: <String, Object?>{
        'email': 'backend.test@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
    );
    expect(register.statusCode, 201);
    final registerBody = await _decodeBody(register);
    expect(registerBody['ok'], true);
    expect((registerBody['user_id'] as String?)?.isNotEmpty, true);

    final login = await _postJson(
      handler,
      '/auth/login',
      body: <String, Object?>{
        'email': 'backend.test@example.com',
        'password': 'SuperSecret123',
      },
    );
    expect(login.statusCode, 200);
    final loginBody = await _decodeBody(login);
    expect((loginBody['token'] as String?)?.isNotEmpty, true);
  });
}

Future<Response> _postJson(
  Handler handler,
  String path, {
  required Map<String, Object?> body,
  String? idempotencyKey,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (idempotencyKey != null) {
    headers['idempotency-key'] = idempotencyKey;
  }
  final request = shelf.Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: headers,
    body: jsonEncode(body),
  );
  final response = await handler(request);
  return response;
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
