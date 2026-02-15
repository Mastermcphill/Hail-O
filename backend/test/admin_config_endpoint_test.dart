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
    'admin config endpoint is admin-only and returns safe flags only',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());

      final handler = _buildHandler(db);
      final riderToken = await _registerAndLogin(
        handler,
        email: 'cfg.rider@example.com',
        role: 'rider',
        idSuffix: 'cfg-rider',
      );
      final adminToken = await _registerAndLogin(
        handler,
        email: 'cfg.admin@example.com',
        role: 'admin',
        idSuffix: 'cfg-admin',
      );

      final unauthorized = await _request(
        handler,
        method: 'GET',
        path: '/admin/config',
        token: riderToken,
      );
      expect(unauthorized.statusCode, 403);
      final unauthorizedBody = await _decodeBody(unauthorized);
      expect(unauthorizedBody['code'], 'admin_only');

      final authed = await _request(
        handler,
        method: 'GET',
        path: '/admin/config',
        token: adminToken,
      );
      expect(authed.statusCode, 200);
      final body = await _decodeBody(authed);
      expect(body['ok'], isTrue);

      final config = Map<String, Object?>.from(
        body['config'] as Map<String, Object?>,
      );
      expect(config['db_mode'], 'postgres');
      expect(config['db_schema'], 'hailo_staging');
      expect(config['rate_limit_enabled'], isTrue);
      expect(config['metrics_protected'], isTrue);
      expect(config.containsKey('jwt_secret'), isFalse);
      expect(config.containsKey('database_url'), isFalse);
      expect(config.containsKey('password'), isFalse);
    },
  );
}

Handler _buildHandler(Database db) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'postgres',
    environment: 'staging',
    requestMetrics: RequestMetrics(),
    dbHealthCheck: () async => true,
    buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
    runtimeConfigSnapshot: const <String, Object?>{
      'environment': 'staging',
      'db_mode': 'postgres',
      'db_schema': 'hailo_staging',
      'cors_enabled': false,
      'allowed_origins_count': 0,
      'rate_limit_enabled': true,
      'rate_limit_window_seconds': 60,
      'rate_limit_max_requests_per_ip': 60,
      'rate_limit_max_requests_per_user': 120,
      'metrics_public': false,
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
  final register = await _request(
    handler,
    method: 'POST',
    path: '/auth/register',
    idempotencyKey: 'register-$idSuffix',
    body: <String, Object?>{
      'email': email,
      'password': 'SuperSecret123',
      'role': role,
      'display_name': 'Config $role',
    },
  );
  expect(register.statusCode, 201);

  final login = await _request(
    handler,
    method: 'POST',
    path: '/auth/login',
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

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
