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

  test(
    'invalid JSON response has stable error envelope with trace_id',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());

      final handler = _buildHandler(db);
      final response = await handler(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          headers: const <String, String>{
            'content-type': 'application/json',
            'idempotency-key': 'invalid-json-envelope-1',
          },
          body: '{',
        ),
      );

      expect(response.statusCode, 400);
      final envelope = await _decodeEnvelope(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['code'], 'invalid_format');
      expect((envelope['message'] as String?)?.isNotEmpty, isTrue);
      expect((envelope['trace_id'] as String?)?.isNotEmpty, isTrue);
    },
  );

  test(
    'missing auth response has stable error envelope with trace_id',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());

      final handler = _buildHandler(db);
      final response = await handler(
        shelf.Request('GET', Uri.parse('http://localhost/rides/ride-123')),
      );

      expect(response.statusCode, 401);
      final envelope = await _decodeEnvelope(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['code'], 'unauthorized');
      expect((envelope['trace_id'] as String?)?.isNotEmpty, isTrue);
    },
  );

  test('validation error has stable code and trace_id', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(db);
    final response = await handler(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/auth/register'),
        headers: const <String, String>{
          'content-type': 'application/json',
          'idempotency-key': 'invalid-email-envelope-1',
        },
        body: jsonEncode(<String, Object?>{
          'email': 'bad-email',
          'password': 'SuperSecret123',
          'role': 'rider',
        }),
      ),
    );

    expect(response.statusCode, 409);
    final envelope = await _decodeEnvelope(response);
    expect(envelope['ok'], isFalse);
    expect(envelope['code'], 'invalid_email');
    expect((envelope['trace_id'] as String?)?.isNotEmpty, isTrue);
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

Future<Map<String, Object?>> _decodeEnvelope(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
