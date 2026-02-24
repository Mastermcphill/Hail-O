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

  test('/me/documents persists and validates cross-border documents', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final unauthenticatedNextOfKin = await _request(
      handler,
      method: 'GET',
      path: '/me/next-of-kin',
    );
    expect(unauthenticatedNextOfKin.statusCode, 401);
    final unauthenticatedBody = await _decodeBody(unauthenticatedNextOfKin);
    expect(unauthenticatedBody['error_code'], 'UNAUTHORIZED');

    final rider = await _registerAndLogin(
      handler,
      email: 'me.docs.rider@example.com',
      role: 'rider',
      registerKey: 'register-me-docs-rider',
      includeNextOfKin: true,
    );

    final getNextOfKin = await _request(
      handler,
      method: 'GET',
      path: '/me/next-of-kin',
      token: rider.token,
    );
    expect(getNextOfKin.statusCode, 200);
    final nextOfKinBody = await _decodeBody(getNextOfKin);
    final nextOfKin = Map<String, Object?>.from(
      (nextOfKinBody['next_of_kin'] as Map?) ?? const <String, Object?>{},
    );
    expect(nextOfKin['full_name'], 'Jane Emergency');

    final upsertDocument = await _postJson(
      handler,
      '/me/documents',
      token: rider.token,
      idempotencyKey: 'me-doc-upsert-1',
      body: <String, Object?>{
        'doc_type': 'passport',
        'file_ref': 'local://passport_front.png',
        'country': 'NG',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 365))
            .toIso8601String(),
        'verified': true,
      },
    );
    expect(upsertDocument.statusCode, 201);
    final upsertBody = await _decodeBody(upsertDocument);
    final document = Map<String, Object?>.from(
      (upsertBody['document'] as Map?) ?? const <String, Object?>{},
    );
    expect(document['doc_type'], 'passport');
    expect(document['status'], 'verified');

    final getDocuments = await _request(
      handler,
      method: 'GET',
      path: '/me/documents',
      token: rider.token,
    );
    expect(getDocuments.statusCode, 200);
    final documentsBody = await _decodeBody(getDocuments);
    final documents =
        (documentsBody['documents'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .toList(growable: false);
    expect(documents, isNotEmpty);

    final crossBorderCheck = await _request(
      handler,
      method: 'GET',
      path: '/me/documents?valid_for=international',
      token: rider.token,
    );
    expect(crossBorderCheck.statusCode, 200);
    final crossBorderBody = await _decodeBody(crossBorderCheck);
    expect(crossBorderBody['has_valid_cross_border_document'], isTrue);
  });

  test('/routes enforces role checks and matches published routes', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    final handler = _buildHandler(db);

    final unauthenticatedMatch = await _request(
      handler,
      method: 'GET',
      path: '/routes/match?from=lagos&to=abuja',
    );
    expect(unauthenticatedMatch.statusCode, 401);
    final unauthenticatedMatchBody = await _decodeBody(unauthenticatedMatch);
    expect(unauthenticatedMatchBody['error_code'], 'UNAUTHORIZED');

    final rider = await _registerAndLogin(
      handler,
      email: 'routes.rider@example.com',
      role: 'rider',
      registerKey: 'register-routes-rider',
      includeNextOfKin: true,
    );
    final driver = await _registerAndLogin(
      handler,
      email: 'routes.driver@example.com',
      role: 'driver',
      registerKey: 'register-routes-driver',
    );

    final riderCreateRoute = await _postJson(
      handler,
      '/routes/',
      token: rider.token,
      idempotencyKey: 'routes-create-rider-1',
      body: const <String, Object?>{
        'nodes': <Map<String, Object?>>[
          <String, Object?>{'name': 'Lagos'},
          <String, Object?>{'name': 'Ibadan'},
        ],
      },
    );
    expect(riderCreateRoute.statusCode, 403);
    final riderCreateRouteBody = await _decodeBody(riderCreateRoute);
    expect(riderCreateRouteBody['error_code'], 'FORBIDDEN');

    final driverCreateRoute = await _postJson(
      handler,
      '/routes/',
      token: driver.token,
      idempotencyKey: 'routes-create-driver-1',
      body: const <String, Object?>{
        'nodes': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'Lagos',
            'latitude': 6.455,
            'longitude': 3.384,
          },
          <String, Object?>{
            'name': 'Ibadan',
            'latitude': 7.377,
            'longitude': 3.947,
          },
          <String, Object?>{
            'name': 'Abuja',
            'latitude': 9.076,
            'longitude': 7.398,
          },
        ],
        'is_online': true,
      },
    );
    expect(driverCreateRoute.statusCode, 201);
    final createRouteBody = await _decodeBody(driverCreateRoute);
    final route = Map<String, Object?>.from(
      (createRouteBody['route'] as Map?) ?? const <String, Object?>{},
    );
    final routeId = (route['id'] as String?) ?? '';
    expect(routeId, isNotEmpty);

    final match = await _request(
      handler,
      method: 'GET',
      path: '/routes/match?from=lagos&to=abuja',
      token: rider.token,
    );
    expect(match.statusCode, 200);
    final matchBody = await _decodeBody(match);
    final matches =
        (matchBody['matches'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false);
    expect(matches, isNotEmpty);
    expect(matches.any((row) => row['id'] == routeId), isTrue);
  });

  test(
    '/rides offers -> paywall -> seats flow returns persisted state',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() async => db.close());
      final handler = _buildHandler(db);

      final rider = await _registerAndLogin(
        handler,
        email: 'offers.rider@example.com',
        role: 'rider',
        registerKey: 'register-offers-rider',
        includeNextOfKin: true,
      );
      final driver = await _registerAndLogin(
        handler,
        email: 'offers.driver@example.com',
        role: 'driver',
        registerKey: 'register-offers-driver',
      );

      final requestRide = await _postJson(
        handler,
        '/rides/request',
        token: rider.token,
        idempotencyKey: 'rides-request-offers-1',
        body: <String, Object?>{
          'trip_scope': 'intra_city',
          'scheduled_departure_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 2))
              .toIso8601String(),
          'distance_meters': 18000,
          'duration_seconds': 2200,
          'luggage_count': 1,
          'vehicle_class': 'suv',
          'base_fare_minor': 32000,
          'premium_markup_minor': 3000,
        },
      );
      expect(requestRide.statusCode, 201);
      final requestBody = await _decodeBody(requestRide);
      final rideId = (requestBody['ride_id'] as String?) ?? '';
      expect(rideId, isNotEmpty);

      final submitOffer = await _postJson(
        handler,
        '/rides/$rideId/offers',
        token: driver.token,
        idempotencyKey: 'rides-submit-offer-1',
        body: const <String, Object?>{
          'price_minor': 35500,
          'vehicle_class': 'suv',
        },
      );
      expect(<int>[200, 201], contains(submitOffer.statusCode));
      final submitOfferBody = await _decodeBody(submitOffer);
      final offer = Map<String, Object?>.from(
        (submitOfferBody['offer'] as Map?) ?? const <String, Object?>{},
      );
      final offerId = (offer['offer_id'] as String?) ?? '';
      expect(offerId, isNotEmpty);

      final listOffers = await _request(
        handler,
        method: 'GET',
        path: '/rides/$rideId/offers',
        token: rider.token,
      );
      expect(listOffers.statusCode, 200);
      final offersBody = await _decodeBody(listOffers);
      final offers =
          (offersBody['offers'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((row) => Map<String, Object?>.from(row))
              .toList(growable: false);
      expect(offers, isNotEmpty);

      final acceptOffer = await _postJson(
        handler,
        '/rides/$rideId/accept-offer',
        token: rider.token,
        idempotencyKey: 'rides-accept-offer-1',
        body: <String, Object?>{'offer_id': offerId},
      );
      expect(acceptOffer.statusCode, 200);
      final acceptBody = await _decodeBody(acceptOffer);
      expect(
        (acceptBody['connection_fee_minor'] as num?)?.toInt() ?? 0,
        greaterThan(0),
      );

      final openPaywall = await _postJson(
        handler,
        '/rides/$rideId/paywall/open',
        token: rider.token,
        idempotencyKey: 'rides-open-paywall-1',
        body: const <String, Object?>{},
      );
      expect(openPaywall.statusCode, 200);
      final openPaywallBody = await _decodeBody(openPaywall);
      expect(openPaywallBody['expired'], isFalse);

      final payPaywall = await _postJson(
        handler,
        '/rides/$rideId/paywall/pay',
        token: rider.token,
        idempotencyKey: 'rides-pay-paywall-1',
        body: const <String, Object?>{},
      );
      expect(payPaywall.statusCode, 200);
      final payPaywallBody = await _decodeBody(payPaywall);
      expect(payPaywallBody['ok'], isTrue);
      expect(payPaywallBody['connection_fee_paid'], isTrue);

      final getSeats = await _request(
        handler,
        method: 'GET',
        path: '/rides/$rideId/seats',
        token: rider.token,
      );
      expect(getSeats.statusCode, 200);
      final seatsBody = await _decodeBody(getSeats);
      final seats = (seatsBody['seats'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
      expect(seats, isNotEmpty);
      final firstSeatId = (seats.first['seat_id'] as String?) ?? '';
      expect(firstSeatId, isNotEmpty);

      final selectSeat = await _postJson(
        handler,
        '/rides/$rideId/seats/select',
        token: rider.token,
        idempotencyKey: 'rides-select-seat-1',
        body: <String, Object?>{
          'seat_ids': <String>[firstSeatId],
          'charter_mode': false,
        },
      );
      expect(selectSeat.statusCode, 200);
      final selectSeatBody = await _decodeBody(selectSeat);
      expect((selectSeatBody['purchase_id'] as String?)?.isNotEmpty, isTrue);
      expect(
        (selectSeatBody['pricing_minor'] as num?)?.toInt() ?? 0,
        greaterThan(0),
      );
    },
  );
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

Future<_AuthResult> _registerAndLogin(
  Handler handler, {
  required String email,
  required String role,
  required String registerKey,
  bool includeNextOfKin = false,
}) async {
  final registerPayload = <String, Object?>{
    'email': email,
    'password': 'SuperSecret123',
    'role': role,
  };
  if (includeNextOfKin) {
    registerPayload['next_of_kin'] = const <String, Object?>{
      'full_name': 'Jane Emergency',
      'phone': '+2348011111111',
      'relationship': 'sibling',
    };
  }

  final register = await _postJson(
    handler,
    '/auth/register',
    idempotencyKey: registerKey,
    body: registerPayload,
  );
  expect(register.statusCode, 201);
  final registerBody = await _decodeBody(register);
  final userId = (registerBody['user_id'] as String?) ?? '';
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
  final request = shelf.Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: headers,
    body: body == null ? '' : jsonEncode(body),
  );
  return handler(request);
}

Future<Response> _postJson(
  Handler handler,
  String path, {
  required Map<String, Object?> body,
  String? token,
  String? idempotencyKey,
}) {
  return _request(
    handler,
    method: 'POST',
    path: path,
    token: token,
    idempotencyKey: idempotencyKey,
    body: body,
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _AuthResult {
  const _AuthResult({required this.userId, required this.token});

  final String userId;
  final String token;
}
