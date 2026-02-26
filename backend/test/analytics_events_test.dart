import 'dart:convert';

import 'package:crypto/crypto.dart';
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

const String _kSecret = 'backend-test-secret';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('auth OTP flow writes analytics events', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(
      db,
      environmentMap: const <String, String>{
        'ENV': 'test',
        'OTP_DEV_BYPASS': 'true',
        'OTP_DEV_BYPASS_CODE': '123456',
      },
    );

    const phone = '+15559990001';
    final requestOtp = await _request(
      handler,
      method: 'POST',
      path: '/auth/otp/request',
      body: const <String, Object?>{'phone_e164': phone},
    );
    expect(requestOtp.statusCode, 200);

    final verifyOtp = await _request(
      handler,
      method: 'POST',
      path: '/auth/otp/verify',
      body: const <String, Object?>{'phone_e164': phone, 'code': '123456'},
    );
    expect(verifyOtp.statusCode, 200);

    final names = await _analyticsNames(db);
    expect(names, contains('auth.otp_requested'));
    expect(names, contains('auth.otp_verified'));
  });

  test(
    'marketplace, payments, and dispatch flows write analytics events',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      const webhookSecret = 'analytics-paystack-webhook';
      final handler = _buildHandler(
        db,
        environmentMap: const <String, String>{
          'ENV': 'test',
          'PAYMENTS_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'test-paystack-secret',
          'PAYSTACK_WEBHOOK_SECRET': webhookSecret,
        },
      );

      final rider = await _registerAndLogin(
        handler,
        email: 'analytics.rider@example.com',
        role: 'rider',
        registerKey: 'analytics-rider-register',
      );
      final driver = await _registerAndLogin(
        handler,
        email: 'analytics.driver@example.com',
        role: 'driver',
        registerKey: 'analytics-driver-register',
      );

      final offers = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/offers',
        token: rider.token,
      );
      expect(offers.statusCode, 200);

      final purchaseResponse = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        token: rider.token,
        idempotencyKey: 'analytics-purchase-create',
        body: const <String, Object?>{
          'offer_id': 'offer_sedan_01',
          'quantity': 1,
        },
      );
      expect(purchaseResponse.statusCode, 200);
      final purchaseBody = await _decodeBody(purchaseResponse);
      final purchaseData = Map<String, Object?>.from(
        (purchaseBody['data'] as Map?) ?? const <String, Object?>{},
      );
      final purchase = Map<String, Object?>.from(
        (purchaseData['purchase'] as Map?) ?? const <String, Object?>{},
      );
      final purchaseId = (purchase['purchase_id'] as String?) ?? '';
      expect(purchaseId.isNotEmpty, isTrue);

      final intentResponse = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        token: rider.token,
        idempotencyKey: 'analytics-intent-create',
        body: <String, Object?>{'purchase_id': purchaseId},
      );
      expect(intentResponse.statusCode, 200);

      final webhookPayload = <String, Object?>{
        'event': 'charge.success',
        'data': <String, Object?>{
          'id': 'evt-analytics-success-1',
          'metadata': <String, Object?>{'purchase_id': purchaseId},
        },
      };
      final webhookRawBody = jsonEncode(webhookPayload);
      final webhookSignature = Hmac(
        sha512,
        utf8.encode(webhookSecret),
      ).convert(utf8.encode(webhookRawBody)).toString();
      final webhookResponse = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        headers: <String, String>{'x-paystack-signature': webhookSignature},
        rawBody: webhookRawBody,
      );
      expect(webhookResponse.statusCode, 200);

      final quote = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/quote',
        token: rider.token,
        body: const <String, Object?>{
          'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
          'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
        },
      );
      expect(quote.statusCode, 200);

      final tripCreate = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/trips',
        token: rider.token,
        body: const <String, Object?>{
          'pickup': <String, Object?>{'lat': 6.455, 'lng': 3.384},
          'dropoff': <String, Object?>{'lat': 6.6018, 'lng': 3.3515},
        },
      );
      expect(tripCreate.statusCode, 201);
      final tripBody = await _decodeBody(tripCreate);
      final trip = Map<String, Object?>.from(
        (tripBody['trip'] as Map?) ?? const <String, Object?>{},
      );
      final tripId = (trip['id'] as String?) ?? '';
      expect(tripId.isNotEmpty, isTrue);

      final assign = await _request(
        handler,
        method: 'POST',
        path: '/dispatch/trips/$tripId/assign',
        token: rider.token,
        body: <String, Object?>{'driver_id': driver.userId},
      );
      expect(assign.statusCode, 200);

      final statusSequence = <String>[
        'enroute_pickup',
        'picked_up',
        'enroute_dropoff',
        'delivered',
      ];
      for (final status in statusSequence) {
        final response = await _request(
          handler,
          method: 'POST',
          path: '/dispatch/trips/$tripId/status',
          token: rider.token,
          body: <String, Object?>{'status': status},
        );
        expect(response.statusCode, 200);
      }

      final names = await _analyticsNames(db);
      expect(names, contains('marketplace.offers_listed'));
      expect(names, contains('marketplace.purchase_created'));
      expect(names, contains('payments.intent_created'));
      expect(names, contains('payments.webhook_received'));
      expect(names, contains('payments.succeeded'));
      expect(names, contains('dispatch.quote_created'));
      expect(names, contains('dispatch.trip_created'));
      expect(names, contains('dispatch.trip_assigned'));
      expect(names, contains('dispatch.trip_delivered'));
    },
  );

  test('admin moderation writes analytics events', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final rider = await _registerAndLogin(
      handler,
      email: 'analytics.admin.target@example.com',
      role: 'rider',
      registerKey: 'analytics-admin-target-register',
    );
    final adminToken = TokenService(
      secret: _kSecret,
    ).issueToken(userId: 'analytics-admin', role: 'admin');

    final disable = await _request(
      handler,
      method: 'POST',
      path: '/admin/users/${rider.userId}/disable',
      token: adminToken,
    );
    expect(disable.statusCode, 200);

    final enable = await _request(
      handler,
      method: 'POST',
      path: '/admin/users/${rider.userId}/enable',
      token: adminToken,
    );
    expect(enable.statusCode, 200);

    final names = await _analyticsNames(db);
    expect(names, contains('admin.user_disabled'));
    expect(names, contains('admin.user_enabled'));
  });
}

Handler _buildHandler(
  Database db, {
  Map<String, String> environmentMap = const <String, String>{'ENV': 'test'},
}) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: _kSecret),
    dbMode: 'sqlite',
    environment: (environmentMap['ENV'] ?? 'test'),
    requestMetrics: RequestMetrics(),
    dbHealthCheck: () async => true,
    buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
    environmentMap: environmentMap,
  ).buildHandler();
}

Future<_AuthSession> _registerAndLogin(
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
  Map<String, String> headers = const <String, String>{},
  Map<String, Object?>? body,
  String? rawBody,
}) {
  final requestHeaders = <String, String>{
    'content-type': 'application/json',
    ...headers,
  };
  if (token != null && token.trim().isNotEmpty) {
    requestHeaders['authorization'] = 'Bearer ${token.trim()}';
  }
  final normalizedMethod = method.trim().toUpperCase();
  final resolvedIdempotencyKey = (idempotencyKey?.trim().isNotEmpty ?? false)
      ? idempotencyKey!.trim()
      : normalizedMethod == 'POST'
      ? 'analytics-test-key-${_requestCounter++}'
      : null;
  if (resolvedIdempotencyKey != null) {
    requestHeaders['idempotency-key'] = resolvedIdempotencyKey;
  }
  final request = shelf.Request(
    normalizedMethod,
    Uri.parse('http://localhost$path'),
    headers: requestHeaders,
    body: rawBody ?? (body == null ? '' : jsonEncode(body)),
  );
  return Future<Response>.value(handler(request));
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

Future<Set<String>> _analyticsNames(Database db) async {
  final rows = await db.query(
    'analytics_events',
    columns: const <String>['name'],
    orderBy: 'created_at DESC',
  );
  return rows
      .map((row) => ((row['name'] as String?) ?? '').trim())
      .where((name) => name.isNotEmpty)
      .toSet();
}

class _AuthSession {
  const _AuthSession({required this.userId, required this.token});

  final String userId;
  final String token;
}

int _requestCounter = 0;
