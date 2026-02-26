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

  test('/me requires auth', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final response = await _request(handler, method: 'GET', path: '/me');
    expect(response.statusCode, 401);
    final body = await _decodeBody(response);
    expect(body['error_code'], 'UNAUTHORIZED');
  });

  test('profile update persists', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final token = await _registerAndLogin(
      handler,
      email: 'profile.persist@example.com',
      role: 'rider',
      registerKey: 'register-profile-persist',
    );

    final patch = await _request(
      handler,
      method: 'PATCH',
      path: '/me',
      token: token,
      body: const <String, Object?>{
        'name': 'Profile Persist',
        'email': 'profile.updated@example.com',
        'avatar_url': 'https://cdn.example.com/avatar.png',
      },
    );
    expect(patch.statusCode, 200);
    final patchBody = await _decodeBody(patch);
    final patchedProfile = Map<String, Object?>.from(
      (patchBody['profile'] as Map?) ?? const <String, Object?>{},
    );
    expect(patchedProfile['display_name'], 'Profile Persist');
    expect(patchedProfile['email'], 'profile.updated@example.com');
    expect(patchedProfile['avatar_url'], 'https://cdn.example.com/avatar.png');

    final getProfile = await _request(
      handler,
      method: 'GET',
      path: '/me',
      token: token,
    );
    expect(getProfile.statusCode, 200);
    final getBody = await _decodeBody(getProfile);
    final profile = Map<String, Object?>.from(
      (getBody['profile'] as Map?) ?? const <String, Object?>{},
    );
    expect(profile['display_name'], 'Profile Persist');
    expect(profile['email'], 'profile.updated@example.com');
    expect(profile['avatar_url'], 'https://cdn.example.com/avatar.png');
  });

  test('role list returns expected roles', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final token = await _registerAndLogin(
      handler,
      email: 'roles.driver@example.com',
      role: 'driver',
      registerKey: 'register-roles-driver',
    );

    final response = await _request(
      handler,
      method: 'GET',
      path: '/me/roles',
      token: token,
    );
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    final roles = (body['roles'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);
    expect(roles, contains('user'));
    expect(roles, contains('driver'));
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

Future<String> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String registerKey,
}) async {
  final register = await _request(
    handler,
    method: 'POST',
    path: '/auth/register',
    idempotencyKey: registerKey,
    body: <String, Object?>{
      'email': email,
      'password': 'SuperSecret123',
      'role': role,
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
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
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
