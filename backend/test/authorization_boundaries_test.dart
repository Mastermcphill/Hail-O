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

  test('rider role cannot call driver-only ride actions', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final riderToken = await _registerAndLogin(
      handler,
      email: 'boundary.rider@example.com',
      role: 'rider',
      idSuffix: 'rider-only',
    );

    for (final path in <String>[
      '/rides/ride-boundary/accept',
      '/rides/ride-boundary/start',
      '/rides/ride-boundary/complete',
    ]) {
      final response = await _postJson(
        handler,
        path,
        token: riderToken,
        idempotencyKey: 'idem-$path-rider',
        body: const <String, Object?>{},
      );
      expect(response.statusCode, 403);
      final envelope = await _decodeBody(response);
      expect(envelope['code'], 'forbidden');
      expect((envelope['trace_id'] as String?)?.isNotEmpty, isTrue);
    }
  });

  test('driver role cannot call admin-only endpoints', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final driverToken = await _registerAndLogin(
      handler,
      email: 'boundary.driver@example.com',
      role: 'driver',
      idSuffix: 'driver-only',
    );

    final adminReversal = await _postJson(
      handler,
      '/admin/reversal',
      token: driverToken,
      idempotencyKey: 'idem-admin-reversal-driver',
      body: const <String, Object?>{
        'original_ledger_id': 1,
        'reason': 'boundary_test',
      },
    );
    expect(adminReversal.statusCode, 403);
    final reversalBody = await _decodeBody(adminReversal);
    expect(reversalBody['code'], 'admin_only');

    final adminConfig = await _request(
      handler,
      method: 'GET',
      path: '/admin/config',
      token: driverToken,
    );
    expect(adminConfig.statusCode, 403);
    final configBody = await _decodeBody(adminConfig);
    expect(configBody['code'], 'admin_only');

    final settlementRun = await _postJson(
      handler,
      '/settlement/run',
      token: driverToken,
      idempotencyKey: 'idem-settlement-run-driver',
      body: const <String, Object?>{
        'ride_id': 'ride-boundary',
        'escrow_id': 'escrow-boundary',
      },
    );
    expect(settlementRun.statusCode, 403);
    final settlementBody = await _decodeBody(settlementRun);
    expect(settlementBody['code'], 'admin_only');
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
    runtimeConfigSnapshot: const <String, Object?>{
      'rate_limit_enabled': true,
      'metrics_protected': true,
    },
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
  ).buildHandler();
}

Future<String> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String idSuffix,
}) async {
  final register = await _postJson(
    handler,
    '/auth/register',
    idempotencyKey: 'register-$idSuffix',
    body: <String, Object?>{
      'email': email,
      'password': 'SuperSecret123',
      'role': role,
      'display_name': 'Boundary $role',
    },
  );
  expect(register.statusCode, 201);

  final login = await _postJson(
    handler,
    '/auth/login',
    body: <String, Object?>{'email': email, 'password': 'SuperSecret123'},
  );
  expect(login.statusCode, 200);
  final loginBody = await _decodeBody(login);
  final token = (loginBody['token'] as String?) ?? '';
  expect(token.isNotEmpty, isTrue);
  return token;
}

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (idempotencyKey != null) {
    headers['idempotency-key'] = idempotencyKey;
  }

  return handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body == null ? '' : jsonEncode(body),
    ),
  );
}

Future<Response> _postJson(
  Handler handler,
  String path, {
  Map<String, Object?>? body,
  String? token,
  String? idempotencyKey,
}) {
  return _request(
    handler,
    method: 'POST',
    path: path,
    token: token,
    idempotencyKey: idempotencyKey,
    body: body ?? const <String, Object?>{},
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
