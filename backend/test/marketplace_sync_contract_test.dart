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
    'marketplace sync contract supports etag, timeline since, and version conflict',
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
        environmentMap: const <String, String>{
          'PAYMENT_PROVIDER': 'manual',
          'PAYMENT_WEBHOOK_SECRET': 'manual-secret',
        },
      ).buildHandler();

      final riderToken = await _registerAndLogin(
        handler,
        email: 'sync.rider@example.com',
        role: 'rider',
        idSuffix: 'sync-rider',
      );

      final offers = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/offers',
        token: riderToken,
      );
      expect(offers.statusCode, 200);
      final offersEtag = offers.headers['etag'];
      expect(offersEtag, isNotNull);

      final offersNotModified = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/offers',
        token: riderToken,
        extraHeaders: <String, String>{'if-none-match': offersEtag!},
      );
      expect(offersNotModified.statusCode, 304);

      final offersBody = await _decodeBody(offers);
      final offerId =
          ((offersBody['data'] as List).first as Map)['id'] as String? ?? '';
      expect(offerId.isNotEmpty, isTrue);

      final createPurchase = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        token: riderToken,
        idempotencyKey: 'sync-idem-1',
        body: <String, Object?>{'offerId': offerId, 'seatCount': 2},
      );
      expect(createPurchase.statusCode, anyOf(200, 201));
      final createBody = await _decodeBody(createPurchase);
      final createdData = Map<String, Object?>.from(
        createBody['data'] as Map<String, Object?>,
      );
      final purchaseId = (createdData['purchaseId'] as String?) ?? '';
      final version = (createdData['version'] as num?)?.toInt() ?? 1;
      expect(purchaseId.isNotEmpty, isTrue);
      expect(version, greaterThan(0));

      final purchase = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/$purchaseId',
        token: riderToken,
      );
      expect(purchase.statusCode, 200);
      final purchaseEtag = purchase.headers['etag'];
      expect(purchaseEtag, isNotNull);

      final purchaseNotModified = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/$purchaseId',
        token: riderToken,
        extraHeaders: <String, String>{'if-none-match': purchaseEtag!},
      );
      expect(purchaseNotModified.statusCode, 304);

      final seatConflict = await _request(
        handler,
        method: 'PATCH',
        path: '/marketplace/purchases/$purchaseId/seats',
        token: riderToken,
        extraHeaders: const <String, String>{'if-match-version': '999999'},
        body: <String, Object?>{'seatCount': 3},
      );
      expect(seatConflict.statusCode, 409);
      final conflictBody = await _decodeBody(seatConflict);
      expect(conflictBody['error_code'], 'VERSION_CONFLICT');
      final latest = Map<String, Object?>.from(
        (conflictBody['data'] as Map)['latest'] as Map,
      );
      expect(latest['purchaseId'], purchaseId);
      expect((latest['version'] as num?)?.toInt(), version);

      final seatUpdate = await _request(
        handler,
        method: 'PATCH',
        path: '/marketplace/purchases/$purchaseId/seats',
        token: riderToken,
        extraHeaders: <String, String>{'if-match-version': '$version'},
        body: <String, Object?>{'seatCount': 3},
      );
      expect(seatUpdate.statusCode, 200);
      final seatBody = await _decodeBody(seatUpdate);
      final updatedData = Map<String, Object?>.from(
        seatBody['data'] as Map<String, Object?>,
      );
      final updatedVersion = (updatedData['version'] as num?)?.toInt() ?? 1;
      expect(updatedVersion, greaterThan(version));
      final updatedAssignments =
          (updatedData['assignments'] as List?) ?? const <Object?>[];
      final ownerAssignee = updatedAssignments.isNotEmpty
          ? ((updatedAssignments.first as Map)['email'] as String?) ?? ''
          : '';
      expect(ownerAssignee.isNotEmpty, isTrue);

      final timeline = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/$purchaseId/timeline',
        token: riderToken,
      );
      expect(timeline.statusCode, 200);
      final timelineBody = await _decodeBody(timeline);
      final timelineData = Map<String, Object?>.from(
        timelineBody['data'] as Map<String, Object?>,
      );
      final latestEventAt = (timelineData['latest_event_at'] as String?) ?? '';
      expect(latestEventAt.isNotEmpty, isTrue);

      final timelineEtag = timeline.headers['etag'];
      expect(timelineEtag, isNotNull);

      final timelineNotModified = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/$purchaseId/timeline',
        token: riderToken,
        extraHeaders: <String, String>{'if-none-match': timelineEtag!},
      );
      expect(timelineNotModified.statusCode, 304);

      final assignmentUpdate = await _request(
        handler,
        method: 'PATCH',
        path: '/marketplace/purchases/$purchaseId/assignments',
        token: riderToken,
        extraHeaders: <String, String>{'if-match-version': '$updatedVersion'},
        body: <String, Object?>{
          'assignments': <Map<String, Object?>>[
            <String, Object?>{
              'seat_index': 1,
              'user_id': ownerAssignee,
            },
          ],
        },
      );
      expect(assignmentUpdate.statusCode, 200);

      final timelineSince = await _request(
        handler,
        method: 'GET',
        path:
            '/marketplace/purchases/$purchaseId/timeline?since=${Uri.encodeQueryComponent(latestEventAt)}',
        token: riderToken,
      );
      expect(timelineSince.statusCode, 200);
      final timelineSinceBody = await _decodeBody(timelineSince);
      final sinceData = Map<String, Object?>.from(
        timelineSinceBody['data'] as Map<String, Object?>,
      );
      final events =
          (sinceData['events'] as List?)?.cast<Map<String, Object?>>() ??
          const <Map<String, Object?>>[];
      expect(events, isNotEmpty);
      expect(
        events.any(
          (event) =>
              (event['type'] as String?)?.toUpperCase() == 'ASSIGNMENT_UPDATED',
        ),
        isTrue,
      );
    },
  );
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
  Map<String, String>? extraHeaders,
  Map<String, Object?>? body,
}) async {
  final headers = <String, String>{'content-type': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
    headers['idempotency-key'] = idempotencyKey;
  }
  if (extraHeaders != null) {
    headers.addAll(extraHeaders);
  }
  return await handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body == null ? '' : jsonEncode(body),
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final raw = await response.readAsString();
  if (raw.trim().isEmpty) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
