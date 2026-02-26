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

  test('create trip returns created status and payload fields', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final token = await _registerAndLogin(
      handler,
      email: 'dispatch.create@example.com',
      role: 'rider',
      registerKey: 'dispatch-create-register',
    );

    final response = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{
          'lat': 6.455,
          'lng': 3.384,
          'address': 'Lagos Island',
        },
        'dropoff': <String, Object?>{
          'lat': 6.6018,
          'lng': 3.3515,
          'address': 'Ikeja',
        },
        'notes': 'Handle with care',
      },
    );
    expect(response.statusCode, 201);
    final payload = await _decodeBody(response);
    expect(payload['ok'], true);
    final trip = Map<String, Object?>.from(
      (payload['trip'] as Map?) ?? const <String, Object?>{},
    );
    expect((trip['id'] as String?)?.isNotEmpty, isTrue);
    expect(trip['status'], 'created');
    final pickup = Map<String, Object?>.from(
      (trip['pickup'] as Map?) ?? const <String, Object?>{},
    );
    final dropoff = Map<String, Object?>.from(
      (trip['dropoff'] as Map?) ?? const <String, Object?>{},
    );
    expect((pickup['lat'] as num?)?.toDouble(), 6.455);
    expect((dropoff['lng'] as num?)?.toDouble(), 3.3515);
    expect(trip['notes'], 'Handle with care');

    final tripId = (trip['id'] as String?) ?? '';
    final eventRows = await db.query(
      'trip_events',
      where: 'trip_id = ?',
      whereArgs: <Object>[tripId],
    );
    expect(eventRows.length, 1);
    expect(eventRows.first['to_status'], 'created');
  });

  test('invalid lat/lng returns validation error', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final token = await _registerAndLogin(
      handler,
      email: 'dispatch.invalid.latlng@example.com',
      role: 'rider',
      registerKey: 'dispatch-invalid-latlng-register',
    );

    final response = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 120.0, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    expect(response.statusCode, 409);
    final body = await _decodeBody(response);
    expect(body['ok'], isFalse);
    expect(body['error_code'], 'INVALID_PICKUP_LAT');
  });

  test('status transition happy path returns updated trip and event', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final token = await _registerAndLogin(
      handler,
      email: 'dispatch.transition.ok@example.com',
      role: 'rider',
      registerKey: 'dispatch-transition-register',
    );

    final createResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    final createBody = await _decodeBody(createResponse);
    final createdTrip = Map<String, Object?>.from(createBody['trip'] as Map);
    final tripId = (createdTrip['id'] as String?) ?? '';

    final transition = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips/$tripId/status',
      token: token,
      body: const <String, Object?>{
        'status': 'searching',
        'metadata': <String, Object?>{'source': 'test'},
      },
    );
    expect(transition.statusCode, 200);
    final transitionBody = await _decodeBody(transition);
    final trip = Map<String, Object?>.from(transitionBody['trip'] as Map);
    final event = Map<String, Object?>.from(transitionBody['event'] as Map);
    expect(trip['status'], 'searching');
    expect(event['from_status'], 'created');
    expect(event['to_status'], 'searching');
    expect(event['actor_user_id'], isNotNull);
  });

  test(
    'invalid transition returns 409 with structured error and trace_id',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      final handler = _buildHandler(db);
      final token = await _registerAndLogin(
        handler,
        email: 'dispatch.transition.invalid@example.com',
        role: 'rider',
        registerKey: 'dispatch-invalid-transition-register',
      );

      final createResponse = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/trips',
        token: token,
        body: const <String, Object?>{
          'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
          'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
        },
      );
      final createBody = await _decodeBody(createResponse);
      final tripId =
          (Map<String, Object?>.from(createBody['trip'] as Map)['id']
              as String?) ??
          '';

      final response = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/trips/$tripId/status',
        token: token,
        body: const <String, Object?>{'status': 'delivered'},
      );
      expect(response.statusCode, 409);
      final body = await _decodeBody(response);
      expect(body['ok'], isFalse);
      expect(body['error_code'], 'INVALID_STATUS_TRANSITION');
      expect((body['trace_id'] as String?)?.isNotEmpty, isTrue);
    },
  );

  test('list supports pagination with stable ordering', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final token = await _registerAndLogin(
      handler,
      email: 'dispatch.list.pagination@example.com',
      role: 'rider',
      registerKey: 'dispatch-list-register',
    );

    final createdTrips = <Map<String, Object?>>[];
    for (var index = 0; index < 3; index++) {
      final response = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/trips',
        token: token,
        body: <String, Object?>{
          'pickup': <String, Object?>{
            'lat': 6.455 + (index * 0.01),
            'lng': 3.384,
          },
          'dropoff': <String, Object?>{
            'lat': 6.6018,
            'lng': 3.3515 + (index * 0.01),
          },
          'notes': 'trip-$index',
        },
      );
      expect(response.statusCode, 201);
      final body = await _decodeBody(response);
      createdTrips.add(Map<String, Object?>.from(body['trip'] as Map));
    }

    final expected = List<Map<String, Object?>>.from(createdTrips)
      ..sort((left, right) {
        final leftCreatedAt = (left['created_at'] as String?) ?? '';
        final rightCreatedAt = (right['created_at'] as String?) ?? '';
        final createdAtCompare = rightCreatedAt.compareTo(leftCreatedAt);
        if (createdAtCompare != 0) {
          return createdAtCompare;
        }
        final leftId = (left['id'] as String?) ?? '';
        final rightId = (right['id'] as String?) ?? '';
        return rightId.compareTo(leftId);
      });

    final firstPage = await _request(
      handler,
      method: 'GET',
      path: '/dispatch/trips?limit=2',
      token: token,
    );
    expect(firstPage.statusCode, 200);
    final firstBody = await _decodeBody(firstPage);
    final firstTrips =
        (firstBody['trips'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => Map<String, Object?>.from(entry as Map))
            .toList(growable: false);
    expect(firstTrips.length, 2);
    final nextCursor = (firstBody['next_cursor'] as String?) ?? '';
    expect(nextCursor.isNotEmpty, isTrue);

    final secondPage = await _request(
      handler,
      method: 'GET',
      path: '/dispatch/trips?limit=2&cursor=$nextCursor',
      token: token,
    );
    expect(secondPage.statusCode, 200);
    final secondBody = await _decodeBody(secondPage);
    final secondTrips =
        (secondBody['trips'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => Map<String, Object?>.from(entry as Map))
            .toList(growable: false);
    expect(secondTrips.length, 1);

    final allTrips = <Map<String, Object?>>[...firstTrips, ...secondTrips];
    final allIds = allTrips.map((trip) => trip['id'] as String).toList();
    final expectedIds = expected.map((trip) => trip['id'] as String).toList();
    expect(allIds, expectedIds);
    expect(allIds.toSet().length, allIds.length);
  });

  test('assigning driver creates assignment and updates trip status', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final rider = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.rider@example.com',
      role: 'rider',
      registerKey: 'dispatch-assign-rider-register',
    );
    final driver = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.driver@example.com',
      role: 'driver',
      registerKey: 'dispatch-assign-driver-register',
    );

    final createResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: rider.token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    expect(createResponse.statusCode, 201);
    final createBody = await _decodeBody(createResponse);
    final tripId =
        (Map<String, Object?>.from(createBody['trip'] as Map)['id']
            as String?) ??
        '';
    expect(tripId.isNotEmpty, isTrue);

    final assignResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips/$tripId/assign',
      token: rider.token,
      body: <String, Object?>{'driver_id': driver.userId},
    );
    expect(assignResponse.statusCode, 200);
    final assignBody = await _decodeBody(assignResponse);
    final trip = Map<String, Object?>.from(assignBody['trip'] as Map);
    final assignment = Map<String, Object?>.from(
      assignBody['assignment'] as Map,
    );
    expect(trip['status'], 'assigned');
    expect(assignment['trip_id'], tripId);
    expect(assignment['driver_id'], driver.userId);
    expect(assignment['status'], 'assigned');

    final assignmentRows = await db.query(
      'trip_assignments',
      where: 'trip_id = ?',
      whereArgs: <Object>[tripId],
      limit: 1,
    );
    expect(assignmentRows.length, 1);
    expect(assignmentRows.first['driver_id'], driver.userId);
    expect(assignmentRows.first['status'], 'assigned');

    final eventRows = await db.query(
      'trip_events',
      columns: <String>['to_status'],
      where: 'trip_id = ?',
      whereArgs: <Object>[tripId],
      orderBy: 'created_at ASC',
    );
    final statuses = eventRows
        .map((row) => (row['to_status'] as String?) ?? '')
        .toList(growable: false);
    expect(statuses, contains('searching'));
    expect(statuses, contains('assigned'));
  });

  test('assigning again returns 409', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final rider = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.again.rider@example.com',
      role: 'rider',
      registerKey: 'dispatch-assign-again-rider-register',
    );
    final firstDriver = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.again.driver1@example.com',
      role: 'driver',
      registerKey: 'dispatch-assign-again-driver1-register',
    );
    final secondDriver = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.again.driver2@example.com',
      role: 'driver',
      registerKey: 'dispatch-assign-again-driver2-register',
    );

    final createResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: rider.token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    final createBody = await _decodeBody(createResponse);
    final tripId =
        (Map<String, Object?>.from(createBody['trip'] as Map)['id']
            as String?) ??
        '';

    final firstAssign = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips/$tripId/assign',
      token: rider.token,
      body: <String, Object?>{'driver_id': firstDriver.userId},
    );
    expect(firstAssign.statusCode, 200);

    final secondAssign = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips/$tripId/assign',
      token: rider.token,
      body: <String, Object?>{'driver_id': secondDriver.userId},
    );
    expect(secondAssign.statusCode, 409);
    final secondBody = await _decodeBody(secondAssign);
    expect(secondBody['error_code'], 'TRIP_ALREADY_ASSIGNED');
  });

  test('invalid driver_id returns 404', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final rider = await _registerAndLoginSession(
      handler,
      email: 'dispatch.assign.invalid.rider@example.com',
      role: 'rider',
      registerKey: 'dispatch-assign-invalid-rider-register',
    );

    final createResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips',
      token: rider.token,
      body: const <String, Object?>{
        'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
        'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
      },
    );
    final createBody = await _decodeBody(createResponse);
    final tripId =
        (Map<String, Object?>.from(createBody['trip'] as Map)['id']
            as String?) ??
        '';

    final assignResponse = await _request(
      handler,
      method: 'POST',
      path: '/dispatch/trips/$tripId/assign',
      token: rider.token,
      body: const <String, Object?>{
        'driver_id': '00000000-0000-4000-8000-000000000000',
      },
    );
    expect(assignResponse.statusCode, 404);
    final body = await _decodeBody(assignResponse);
    expect(body['error_code'], 'DRIVER_NOT_FOUND');
  });

  test('nearby drivers endpoint returns empty list when none exist', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);
    final riderToken = await _registerAndLogin(
      handler,
      email: 'dispatch.nearby.rider@example.com',
      role: 'rider',
      registerKey: 'dispatch-nearby-rider-register',
    );

    final response = await _request(
      handler,
      method: 'GET',
      path: '/dispatch/drivers/nearby?lat=6.45&lng=3.38&radius_km=10&limit=5',
      token: riderToken,
    );
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], true);
    final drivers = (body['drivers'] as List<dynamic>? ?? const <dynamic>[]);
    expect(drivers, isEmpty);
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
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  final resolvedIdempotencyKey = (idempotencyKey?.trim().isNotEmpty ?? false)
      ? idempotencyKey!.trim()
      : method.toUpperCase() == 'POST'
      ? 'dispatch-test-key-${_requestCounter++}'
      : null;
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (resolvedIdempotencyKey != null) {
    headers['idempotency-key'] = resolvedIdempotencyKey;
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
