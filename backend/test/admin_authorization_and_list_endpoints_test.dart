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

  test('non-admin gets 403 for admin endpoints', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final riderToken = await _registerAndLogin(
      handler,
      email: 'admin.auth.rider@example.com',
      role: 'rider',
      registerKey: 'admin-auth-rider-register',
    );

    final response = await _request(
      handler,
      method: 'GET',
      path: '/admin/health',
      token: riderToken,
    );
    expect(response.statusCode, 403);
    final body = await _decodeBody(response);
    expect(body['error_code'], 'ADMIN_ONLY');
  });

  test('admin gets 200 for health and list endpoints', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final rider = await _registerAndLoginSession(
      handler,
      email: 'admin.list.rider@example.com',
      role: 'rider',
      registerKey: 'admin-list-rider-register',
    );
    final createTrip = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: rider.token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    expect(createTrip.statusCode, 201);
    final createTripBody = await _decodeBody(createTrip);
    final tripId =
        (Map<String, Object?>.from(createTripBody['trip'] as Map)['id']
            as String?) ??
        '';
    expect(tripId.isNotEmpty, isTrue);

    final adminJwt = TokenService(
      secret: _kTestTokenSecret,
    ).issueToken(userId: 'admin-user-1', role: 'admin');

    final health = await _request(
      handler,
      method: 'GET',
      path: '/admin/health',
      token: adminJwt,
    );
    expect(health.statusCode, 200);
    final healthBody = await _decodeBody(health);
    expect(healthBody['ok'], isTrue);
    final diagnostics = Map<String, Object?>.from(
      (healthBody['diagnostics'] as Map?) ?? const <String, Object?>{},
    );
    final counts = Map<String, Object?>.from(
      (diagnostics['counts'] as Map?) ?? const <String, Object?>{},
    );
    expect((counts['users'] as num?)?.toInt() ?? 0, greaterThanOrEqualTo(1));

    final users = await _request(
      handler,
      method: 'GET',
      path: '/admin/users?limit=10',
      token: adminJwt,
    );
    expect(users.statusCode, 200);
    final usersBody = await _decodeBody(users);
    final usersList =
        (usersBody['users'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => Map<String, Object?>.from(entry as Map))
            .toList(growable: false);
    expect(usersList, isNotEmpty);
    expect(usersList.first.containsKey('id'), isTrue);
    expect(usersList.first.containsKey('roles'), isTrue);
    final adminAuditRows = await db.query(
      'audit_logs',
      where: 'action = ? AND resource_type = ?',
      whereArgs: <Object>['admin.list_users', 'admin_endpoint'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    expect(adminAuditRows, isNotEmpty);
    expect(adminAuditRows.first['actor_type'], 'user');
    expect(adminAuditRows.first['actor_user_id'], 'admin-user-1');
    final resourceId = (adminAuditRows.first['resource_id'] as String?) ?? '';
    expect(resourceId == 'users' || resourceId == 'admin/users', isTrue);

    final trips = await _request(
      handler,
      method: 'GET',
      path: '/admin/trips?limit=10',
      token: adminJwt,
    );
    expect(trips.statusCode, 200);
    final tripsBody = await _decodeBody(trips);
    final tripList = (tripsBody['trips'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => Map<String, Object?>.from(entry as Map))
        .toList(growable: false);
    expect(tripList.any((trip) => trip['id'] == tripId), isTrue);
  });

  test('ADMIN_TOKEN bypass works when configured', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(
      db,
      environmentMap: const <String, String>{
        'ENV': 'test',
        'ADMIN_TOKEN': 'emergency-admin-token',
      },
    );

    final response = await _request(
      handler,
      method: 'GET',
      path: '/admin/health',
      headers: const <String, String>{'admin_token': 'emergency-admin-token'},
    );
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], isTrue);
  });

  test(
    'disabled user is denied protected routes and enable restores access',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      final handler = _buildHandler(db);
      final rider = await _registerAndLoginSession(
        handler,
        email: 'admin.moderation.rider@example.com',
        role: 'rider',
        registerKey: 'admin-moderation-rider-register',
      );
      final adminJwt = TokenService(
        secret: _kTestTokenSecret,
      ).issueToken(userId: 'admin-user-1', role: 'admin');

      final meBefore = await _request(
        handler,
        method: 'GET',
        path: '/me',
        token: rider.token,
      );
      expect(meBefore.statusCode, 200);

      final disable = await _request(
        handler,
        method: 'POST',
        path: '/admin/users/${rider.userId}/disable',
        token: adminJwt,
      );
      expect(disable.statusCode, 200);
      final disableBody = await _decodeBody(disable);
      expect(disableBody['disabled'], isTrue);
      await _waitForAuditAction(
        db,
        action: 'admin.disable_user',
        targetUserId: rider.userId,
      );

      final meWhileDisabled = await _request(
        handler,
        method: 'GET',
        path: '/me',
        token: rider.token,
      );
      expect(meWhileDisabled.statusCode, 403);
      final disabledBody = await _decodeBody(meWhileDisabled);
      expect(disabledBody['error_code'], 'USER_DISABLED');

      final enable = await _request(
        handler,
        method: 'POST',
        path: '/admin/users/${rider.userId}/enable',
        token: adminJwt,
      );
      expect(enable.statusCode, 200);
      final enableBody = await _decodeBody(enable);
      expect(enableBody['disabled'], isFalse);
      await _waitForAuditAction(
        db,
        action: 'admin.enable_user',
        targetUserId: rider.userId,
      );

      final meAfter = await _request(
        handler,
        method: 'GET',
        path: '/me',
        token: rider.token,
      );
      expect(meAfter.statusCode, 200);
    },
  );

  test('/admin/metrics returns expected counters shape', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final rider = await _registerAndLoginSession(
      handler,
      email: 'admin.metrics.rider@example.com',
      role: 'rider',
      registerKey: 'admin-metrics-rider-register',
    );
    final createTrip = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: rider.token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    expect(createTrip.statusCode, 201);

    final adminJwt = TokenService(
      secret: _kTestTokenSecret,
    ).issueToken(userId: 'admin-user-1', role: 'admin');
    final response = await _request(
      handler,
      method: 'GET',
      path: '/admin/metrics',
      token: adminJwt,
    );
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], isTrue);
    final counters = Map<String, Object?>.from(body['counters'] as Map);
    expect(counters.containsKey('users'), isTrue);
    expect(counters.containsKey('trips_by_status'), isTrue);
    expect(counters.containsKey('purchases_by_status'), isTrue);
    expect(counters.containsKey('payment_intents_by_status'), isTrue);

    final users = Map<String, Object?>.from(counters['users'] as Map);
    expect((users['total'] as num?)?.toInt() ?? 0, greaterThanOrEqualTo(1));
    expect(users.containsKey('disabled'), isTrue);
    expect(users.containsKey('active'), isTrue);

    final tripsByStatus = Map<String, Object?>.from(
      counters['trips_by_status'] as Map,
    );
    expect(
      (tripsByStatus['created'] as num?)?.toInt() ?? 0,
      greaterThanOrEqualTo(1),
    );
  });
}

Handler _buildHandler(
  Database db, {
  Map<String, String> environmentMap = const <String, String>{},
}) {
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
    environmentMap: environmentMap,
  ).buildHandler();
}

Future<String> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String registerKey,
}) async {
  final session = await _registerAndLoginSession(
    handler,
    email: email,
    role: role,
    registerKey: registerKey,
  );
  return session.token;
}

Future<_AuthSession> _registerAndLoginSession(
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
  final registerBody = await _decodeBody(register);
  final userId = (registerBody['user_id'] as String?) ?? '';
  expect(userId.isNotEmpty, isTrue);

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
  return _AuthSession(userId: userId, token: token);
}

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
  Map<String, String> headers = const <String, String>{},
}) async {
  final requestHeaders = <String, String>{
    'content-type': 'application/json',
    ...headers,
  };
  final resolvedIdempotencyKey = (idempotencyKey?.trim().isNotEmpty ?? false)
      ? idempotencyKey!.trim()
      : method.toUpperCase() == 'POST'
      ? 'admin-v1-test-key-${_requestCounter++}'
      : null;
  if (token != null && token.isNotEmpty) {
    requestHeaders['authorization'] = 'Bearer $token';
  }
  if (resolvedIdempotencyKey != null) {
    requestHeaders['idempotency-key'] = resolvedIdempotencyKey;
  }

  return handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: requestHeaders,
      body: body == null ? '' : jsonEncode(body),
    ),
  );
}

int _requestCounter = 0;

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _AuthSession {
  const _AuthSession({required this.userId, required this.token});

  final String userId;
  final String token;
}

Future<void> _waitForAuditAction(
  Database db, {
  required String action,
  required String targetUserId,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final rows = await db.query(
      'audit_logs',
      where: 'action = ?',
      whereArgs: <Object>[action],
      orderBy: 'created_at DESC',
      limit: 5,
    );
    for (final row in rows) {
      final metadataRaw = (row['metadata'] as String?)?.trim() ?? '';
      if (metadataRaw.isEmpty) {
        continue;
      }
      final metadata = Map<String, Object?>.from(
        jsonDecode(metadataRaw) as Map<String, dynamic>,
      );
      if ((metadata['target_id'] as String?)?.trim() == targetUserId) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Audit action $action for user $targetUserId was not written');
}
