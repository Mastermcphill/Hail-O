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

const String _kTestTokenSecret = 'backend-test-secret';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('non-admin cannot create users via /api/admin/users', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final riderToken = await _registerAndLogin(
      handler,
      email: 'admin.users.rider@example.com',
      role: 'rider',
      idSuffix: 'admin-users-rider',
    );

    final response = await _postJson(
      handler,
      '/api/admin/users',
      token: riderToken,
      idempotencyKey: 'admin-users-rider-create-1',
      body: <String, Object?>{
        'email': 'target.rider@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
    );
    expect(response.statusCode, 403);
    final envelope = await _decodeBody(response);
    expect(envelope['error_code'], 'ADMIN_REQUIRED');
  });

  test('admin can create admin via /api/admin/users', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final adminToken = TokenService(
      secret: _kTestTokenSecret,
    ).issueToken(userId: 'seed-admin-1', role: 'admin');

    final response = await _postJson(
      handler,
      '/api/admin/users',
      token: adminToken,
      idempotencyKey: 'admin-users-create-admin-1',
      body: <String, Object?>{
        'email': 'new.admin@example.com',
        'password': 'SuperSecret123',
        'role': 'admin',
        'display_name': 'New Admin',
      },
    );
    expect(response.statusCode, 201);
    final body = await _decodeBody(response);
    expect(body['role'], 'admin');
    expect((body['user_id'] as String?)?.isNotEmpty, isTrue);
  });

  test('admin users endpoint replays idempotently with same key', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final adminToken = TokenService(
      secret: _kTestTokenSecret,
    ).issueToken(userId: 'seed-admin-2', role: 'admin');

    const key = 'admin-users-replay-1';
    final first = await _postJson(
      handler,
      '/api/admin/users',
      token: adminToken,
      idempotencyKey: key,
      body: <String, Object?>{
        'email': 'replay.user@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
    );
    expect(first.statusCode, 201);
    final firstBody = await _decodeBody(first);
    final firstUserId = (firstBody['user_id'] as String?) ?? '';
    expect(firstUserId, isNotEmpty);

    final replay = await _postJson(
      handler,
      '/api/admin/users',
      token: adminToken,
      idempotencyKey: key,
      body: <String, Object?>{
        'email': 'replay.user@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
    );
    expect(replay.statusCode, 201);
    final replayBody = await _decodeBody(replay);
    expect(replayBody['replayed'], true);
    expect(replayBody['user_id'], firstUserId);
  });
}

Handler _buildHandler(Database db) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: _kTestTokenSecret),
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
      'display_name': 'Admin Users Test $role',
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

Future<Response> _postJson(
  Handler handler,
  String path, {
  required Map<String, Object?> body,
  String? token,
  String? idempotencyKey,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (idempotencyKey != null) {
    headers['idempotency-key'] = idempotencyKey;
  }
  return await handler(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: jsonEncode(body),
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
