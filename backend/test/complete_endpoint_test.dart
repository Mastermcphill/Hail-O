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
    '/rides/{id}/complete succeeds for accepted+started ride and replay is idempotent',
    () async {
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

      final rider = await _registerAndLogin(
        handler,
        email: 'complete.rider@example.com',
        role: 'rider',
        registerKey: 'register-complete-rider',
        includeNextOfKin: true,
      );
      final driver = await _registerAndLogin(
        handler,
        email: 'complete.driver@example.com',
        role: 'driver',
        registerKey: 'register-complete-driver',
      );

      final requestRide = await _postJson(
        handler,
        '/rides/request',
        token: rider.token,
        idempotencyKey: 'request-complete-ride-1',
        body: <String, Object?>{
          'trip_scope': 'intra_city',
          'scheduled_departure_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'distance_meters': 12000,
          'duration_seconds': 2400,
          'luggage_count': 1,
          'vehicle_class': 'sedan',
          'base_fare_minor': 110000,
          'premium_markup_minor': 20000,
        },
      );
      expect(requestRide.statusCode, 201);
      final requestBody = await _decodeBody(requestRide);
      final rideId = (requestBody['ride_id'] as String?) ?? '';
      final escrowId = (requestBody['escrow_id'] as String?) ?? '';
      expect(rideId, isNotEmpty);
      expect(escrowId, isNotEmpty);

      final accept = await _postJson(
        handler,
        '/rides/$rideId/accept',
        token: driver.token,
        idempotencyKey: 'accept-complete-ride-1',
        body: const <String, Object?>{},
      );
      expect(accept.statusCode, 200);

      final start = await _postJson(
        handler,
        '/rides/$rideId/start',
        token: driver.token,
        idempotencyKey: 'start-complete-ride-1',
        body: const <String, Object?>{},
      );
      expect(start.statusCode, 200);

      const completeKey = 'complete-ride-1';
      final completeFirst = await _postJson(
        handler,
        '/rides/$rideId/complete',
        token: driver.token,
        idempotencyKey: completeKey,
        body: <String, Object?>{
          'escrow_id': escrowId,
          'settlement_trigger': 'manual_override',
        },
      );
      expect(completeFirst.statusCode, 200);
      final completeFirstBody = await _decodeBody(completeFirst);
      final settlementFirst = Map<String, Object?>.from(
        (completeFirstBody['settlement'] as Map?) ?? const <String, Object?>{},
      );
      expect(settlementFirst['ok'], true);

      final completeReplay = await _postJson(
        handler,
        '/rides/$rideId/complete',
        token: driver.token,
        idempotencyKey: completeKey,
        body: <String, Object?>{
          'escrow_id': escrowId,
          'settlement_trigger': 'manual_override',
        },
      );
      expect(completeReplay.statusCode, 200);
      final completeReplayBody = await _decodeBody(completeReplay);
      final settlementReplay = Map<String, Object?>.from(
        (completeReplayBody['settlement'] as Map?) ?? const <String, Object?>{},
      );
      expect(settlementReplay['ok'], true);
      expect(settlementReplay['replayed'], true);

      final payoutCountRows = await db.rawQuery(
        'SELECT COUNT(1) AS c FROM payout_records WHERE escrow_id = ?',
        <Object?>[escrowId],
      );
      final payoutCount = (payoutCountRows.first['c'] as int?) ?? 0;
      expect(payoutCount, 1);
    },
  );
}

Future<_AuthResult> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String registerKey,
  bool includeNextOfKin = false,
}) async {
  final registerBody = <String, Object?>{
    'email': email,
    'password': 'SuperSecret123',
    'role': role,
  };
  if (includeNextOfKin) {
    registerBody['next_of_kin'] = <String, Object?>{
      'full_name': 'Jane Emergency',
      'phone': '+2348011111111',
      'relationship': 'sibling',
    };
  }

  final register = await _postJson(
    handler,
    '/auth/register',
    idempotencyKey: registerKey,
    body: registerBody,
  );
  expect(register.statusCode, 201);
  final registerResponseBody = await _decodeBody(register);
  final userId = (registerResponseBody['user_id'] as String?) ?? '';
  expect(userId, isNotEmpty);

  final login = await _postJson(
    handler,
    '/auth/login',
    body: <String, Object?>{'email': email, 'password': 'SuperSecret123'},
  );
  expect(login.statusCode, 200);
  final loginBody = await _decodeBody(login);
  final token = (loginBody['token'] as String?) ?? '';
  expect(token, isNotEmpty);

  return _AuthResult(userId: userId, token: token);
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
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
    headers['idempotency-key'] = idempotencyKey;
  }
  final request = shelf.Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: headers,
    body: jsonEncode(body),
  );
  return await handler(request);
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final raw = await response.readAsString();
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _AuthResult {
  const _AuthResult({required this.userId, required this.token});

  final String userId;
  final String token;
}
