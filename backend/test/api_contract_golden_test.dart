import 'dart:convert';
import 'dart:io';

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

  test('api contract matches v1 golden snapshot', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(db);
    final golden = _loadGolden();
    final endpoints = Map<String, dynamic>.from(
      golden['endpoints'] as Map<String, dynamic>,
    );

    final health = await handler(
      shelf.Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(health.statusCode, 200);
    final healthBody = _decodeResponse(await health.readAsString());
    _assertRequiredKeys(
      response: healthBody,
      requiredKeys: _requiredKeys(endpoints['health'] as Map<String, dynamic>),
    );

    final register = await handler(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        headers: const <String, String>{
          'content-type': 'application/json',
          'idempotency-key': 'golden-register-1',
        },
        body: jsonEncode(<String, Object?>{
          'email': 'golden.contract@example.com',
          'password': 'SuperSecret123',
          'role': 'rider',
        }),
      ),
    );
    expect(register.statusCode, 201);
    final registerBody = _decodeResponse(await register.readAsString());
    _assertRequiredKeys(
      response: registerBody,
      requiredKeys: _requiredKeys(
        endpoints['auth_register'] as Map<String, dynamic>,
      ),
    );
    expect(registerBody['ok'], true);

    final login = await handler(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/auth/login'),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'email': 'golden.contract@example.com',
          'password': 'SuperSecret123',
        }),
      ),
    );
    expect(login.statusCode, 200);
    final loginBody = _decodeResponse(await login.readAsString());
    _assertRequiredKeys(
      response: loginBody,
      requiredKeys: _requiredKeys(
        endpoints['auth_login'] as Map<String, dynamic>,
      ),
    );
    expect((loginBody['token'] as String?)?.isNotEmpty, isTrue);

    final missingIdempotency = await handler(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'email': 'golden.contract.2@example.com',
          'password': 'SuperSecret123',
          'role': 'rider',
        }),
      ),
    );
    expect(missingIdempotency.statusCode, 400);
    final errorBody = _decodeResponse(await missingIdempotency.readAsString());
    _assertRequiredKeys(
      response: errorBody,
      requiredKeys: _requiredKeys(endpoints['error'] as Map<String, dynamic>),
    );
    expect(errorBody['ok'], false);
    expect(errorBody['code'], 'missing_idempotency_key');
  });
}

Map<String, dynamic> _loadGolden() {
  final file = File('test/golden/api_contract_v1.json');
  final raw = file.readAsStringSync();
  return Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>);
}

List<String> _requiredKeys(Map<String, dynamic> section) {
  return List<String>.from(section['required_keys'] as List<dynamic>);
}

Map<String, Object?> _decodeResponse(String raw) {
  return Map<String, Object?>.from(jsonDecode(raw) as Map<String, dynamic>);
}

void _assertRequiredKeys({
  required Map<String, Object?> response,
  required List<String> requiredKeys,
}) {
  for (final key in requiredKeys) {
    expect(
      response.containsKey(key),
      isTrue,
      reason: 'Missing required key "$key" in response: $response',
    );
  }
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
