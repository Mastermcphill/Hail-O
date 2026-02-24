import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../infra/db_provider.dart';
import '../infra/request_context.dart';
import '../infra/request_metrics.dart';
import '../infra/runtime_config.dart';
import '../infra/token_service.dart';
import '../server/app_server.dart';

void main() {
  group('marketplace stub routes', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    final notImplementedCases = <_EndpointCase>[];

    for (final endpoint in notImplementedCases) {
      test(
        '${endpoint.method} ${endpoint.path} returns NOT_IMPLEMENTED envelope',
        () async {
          final response = await _send(
            handler,
            method: endpoint.method,
            path: endpoint.path,
          );

          expect(response.statusCode, 501);
          expect(
            response.headers['content-type'],
            contains('application/json'),
          );

          final payload = await _decodeJsonMap(response);
          expect(payload['ok'], isFalse);
          expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
          expect(payload['error_code'], 'NOT_IMPLEMENTED');
          expect((payload['message'] as String?)?.isNotEmpty, isTrue);
        },
      );
    }

    test(
      'GET /marketplace/offers returns seeded offer list envelope',
      () async {
        final response = await _send(
          handler,
          method: 'GET',
          path: '/marketplace/offers',
        );

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], contains('application/json'));
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isTrue);
        expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
        final data = payload['data'];
        expect(data, isA<List<dynamic>>());
        final offers = (data as List<dynamic>).whereType<Map>().toList();
        expect(offers.length, greaterThanOrEqualTo(3));
        expect(
          offers.any(
            (offer) => (offer['id'] ?? '').toString() == 'offer_sedan_01',
          ),
          isTrue,
        );
      },
    );

    test(
      'GET /api/marketplace/offers returns etag and supports If-None-Match',
      () async {
        final first = await _send(
          handler,
          method: 'GET',
          path: '/api/marketplace/offers',
        );

        expect(first.statusCode, 200);
        final etag = first.headers['etag'];
        expect(etag, isNotNull);
        expect(etag!.isNotEmpty, isTrue);
        final firstPayload = await _decodeJsonMap(first);
        expect(firstPayload['ok'], isTrue);
        expect(firstPayload['data'], isA<List<dynamic>>());

        final notModified = await _send(
          handler,
          method: 'GET',
          path: '/api/marketplace/offers',
          headers: <String, String>{'if-none-match': etag},
        );

        expect(notModified.statusCode, 304);
        expect(notModified.headers['etag'], etag);
        expect(notModified.headers['x-error-code'], isNull);
        final body = await notModified.readAsString();
        expect(body, isEmpty);
      },
    );

    test(
      'GET /marketplace/offers/{offerId}/paywall returns paywall envelope',
      () async {
        final response = await _send(
          handler,
          method: 'GET',
          path: '/marketplace/offers/offer_sedan_01/paywall',
        );

        expect(response.statusCode, 200);
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isTrue);
        expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
        final data = Map<String, dynamic>.from(payload['data'] as Map);
        expect(data['offerId'], 'offer_sedan_01');
        expect((data['headline'] as String?)?.isNotEmpty, isTrue);
        expect((data['bullets'] as List?)?.isNotEmpty, isTrue);
      },
    );

    test(
      'GET /marketplace/offers/{offerId}/paywall unknown offer returns NOT_FOUND',
      () async {
        final response = await _send(
          handler,
          method: 'GET',
          path: '/marketplace/offers/unknown_offer/paywall',
        );

        expect(response.statusCode, 404);
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isFalse);
        expect(payload['error_code'], 'NOT_FOUND');
      },
    );

    test(
      'POST /marketplace/purchases without Idempotency-Key still returns envelope',
      () async {
        final response = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          userId: 'user-rider-1',
          body: const <String, Object?>{
            'offerId': 'offer_sedan_01',
            'seatCount': 2,
          },
        );

        expect(response.statusCode, 400);
        expect(response.headers['content-type'], contains('application/json'));
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isFalse);
        expect(payload['error_code'], 'MISSING_IDEMPOTENCY_KEY');
        expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
      },
    );

    test(
      'POST /marketplace/purchases accepts Idempotency-Key and is idempotent',
      () async {
        final firstResponse = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          userId: 'user-rider-1',
          headers: const <String, String>{
            'idempotency-key': 'purchase-idempotency-1',
          },
          body: const <String, Object?>{
            'offerId': 'offer_sedan_01',
            'seatCount': 3,
          },
        );

        expect(firstResponse.statusCode, 200);
        expect(
          firstResponse.headers['x-idempotency-key'],
          'purchase-idempotency-1',
        );
        final firstPayload = await _decodeJsonMap(firstResponse);
        expect(firstPayload['ok'], isTrue);
        final firstData = Map<String, Object?>.from(
          firstPayload['data'] as Map,
        );
        expect((firstData['purchaseId'] as String?)?.isNotEmpty, isTrue);

        final replayResponse = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          userId: 'user-rider-1',
          headers: const <String, String>{
            'idempotency-key': 'purchase-idempotency-1',
          },
          body: const <String, Object?>{
            'offerId': 'offer_sedan_01',
            'seatCount': 3,
          },
        );
        expect(replayResponse.statusCode, 200);
        final replayPayload = await _decodeJsonMap(replayResponse);
        final replayData = Map<String, Object?>.from(
          replayPayload['data'] as Map,
        );
        expect(replayData['purchaseId'], firstData['purchaseId']);

        final restoredResponse = await _send(
          handler,
          method: 'GET',
          path:
              '/marketplace/purchases/restore?idempotencyKey=purchase-idempotency-1',
          userId: 'user-rider-1',
        );
        expect(restoredResponse.statusCode, 200);
        final restoredPayload = await _decodeJsonMap(restoredResponse);
        final restoredData = Map<String, Object?>.from(
          restoredPayload['data'] as Map,
        );
        expect(restoredData['purchaseId'], firstData['purchaseId']);

        final fetchedResponse = await _send(
          handler,
          method: 'GET',
          path: '/marketplace/purchases/${firstData['purchaseId']}',
          userId: 'user-rider-1',
        );
        expect(fetchedResponse.statusCode, 200);
        final fetchedPayload = await _decodeJsonMap(fetchedResponse);
        final fetchedData = Map<String, Object?>.from(
          fetchedPayload['data'] as Map,
        );
        expect(fetchedData['purchaseId'], firstData['purchaseId']);
        expect(fetchedData['assignments'], isA<List<dynamic>>());

        final seatUpdateResponse = await _send(
          handler,
          method: 'PATCH',
          path: '/marketplace/purchases/${firstData['purchaseId']}/seats',
          userId: 'user-rider-1',
          body: const <String, Object?>{'seat_count': 4},
        );
        expect(seatUpdateResponse.statusCode, 200);
        final seatUpdatePayload = await _decodeJsonMap(seatUpdateResponse);
        final seatUpdateData = Map<String, Object?>.from(
          seatUpdatePayload['data'] as Map,
        );
        expect(seatUpdateData['seatCount'], 4);
        expect(seatUpdateData['status'], 'SEATS_UPDATED');

        final assignmentUpdateResponse = await _send(
          handler,
          method: 'PATCH',
          path: '/marketplace/purchases/${firstData['purchaseId']}/assignments',
          userId: 'user-rider-1',
          body: const <String, Object?>{
            'assignments': <Map<String, Object?>>[
              <String, Object?>{
                'seatIndex': 1,
                'name': 'Ada',
                'email': 'ada@test.dev',
              },
              <String, Object?>{
                'seatIndex': 2,
                'name': 'Kunle',
                'email': 'kunle@test.dev',
              },
            ],
          },
        );
        expect(assignmentUpdateResponse.statusCode, 200);
        final assignmentUpdatePayload = await _decodeJsonMap(
          assignmentUpdateResponse,
        );
        final assignmentUpdateData = Map<String, Object?>.from(
          assignmentUpdatePayload['data'] as Map,
        );
        expect(assignmentUpdateData['status'], 'ASSIGNMENT_UPDATED');

        final planChangeResponse = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases/${firstData['purchaseId']}/change-plan',
          userId: 'user-rider-1',
          headers: const <String, String>{'idempotency-key': 'change-plan-key'},
          body: const <String, Object?>{'new_offer_id': 'offer_suv_02'},
        );
        expect(planChangeResponse.statusCode, 200);
        final planChangePayload = await _decodeJsonMap(planChangeResponse);
        final planChangeData = Map<String, Object?>.from(
          planChangePayload['data'] as Map,
        );
        expect(planChangeData['offerId'], 'offer_suv_02');
        expect(planChangeData['status'], 'PLAN_CHANGED');

        final timelineResponse = await _send(
          handler,
          method: 'GET',
          path: '/marketplace/purchases/${firstData['purchaseId']}/timeline',
          userId: 'user-rider-1',
        );
        expect(timelineResponse.statusCode, 200);
        final timelinePayload = await _decodeJsonMap(timelineResponse);
        expect(timelinePayload['ok'], isTrue);
        final timelineData = Map<String, Object?>.from(
          timelinePayload['data'] as Map,
        );
        final timelineEvents =
            (timelineData['events'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .toList();
        expect(timelineEvents, isNotEmpty);
        expect(
          ((timelineData['latest_event_at'] as String?) ?? '').isNotEmpty,
          isTrue,
        );
        final eventTypes = timelineEvents
            .map((event) => (event['type'] ?? '').toString())
            .toSet();
        expect(eventTypes.contains('PURCHASE_CREATED'), isTrue);
        expect(
          eventTypes.any(
            (type) =>
                type == 'SEAT_ADDED' ||
                type == 'SEAT_REMOVED' ||
                type == 'SEATS_UPDATED',
          ),
          isTrue,
        );
        expect(eventTypes.contains('ASSIGNMENT_UPDATED'), isTrue);
        expect(eventTypes.contains('PLAN_CHANGED'), isTrue);
      },
    );

    test(
      'POST /marketplace/purchases invalid body returns VALIDATION_ERROR',
      () async {
        final response = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          userId: 'user-rider-1',
          headers: const <String, String>{
            'idempotency-key': 'purchase-validation-idempotency',
          },
          body: const <String, Object?>{
            'offerId': 'offer_sedan_01',
            'seatCount': 0,
          },
        );

        expect(response.statusCode, 400);
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isFalse);
        expect(payload['error_code'], 'VALIDATION_ERROR');
        expect((payload['message'] as String?)?.isNotEmpty, isTrue);
        expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
      },
    );

    test('api/healthz remains healthy in postgres mode', () async {
      final response = await _send(
        handler,
        method: 'GET',
        path: '/api/healthz',
      );

      expect(response.statusCode, 200);
      final payload = await _decodeJsonMap(response);
      expect(payload['ok'], isTrue);
      expect(payload['db_mode'], 'postgres');
      expect(payload['db_ok'], isTrue);
    });

    test(
      'POST /webhooks/payments accepts payload and deduplicates events',
      () async {
        const webhookBody = <String, Object?>{
          'provider_event_id': 'evt-marketplace-1',
          'event_type': 'payment_succeeded',
          'purchase_id': '2f15644e-74d1-4952-b45c-55c3695d58dc',
        };

        final first = await _send(
          handler,
          method: 'POST',
          path: '/webhooks/payments',
          body: webhookBody,
        );
        expect(first.statusCode, 200);
        final firstPayload = await _decodeJsonMap(first);
        expect(firstPayload['ok'], isTrue);
        final firstData = Map<String, Object?>.from(
          firstPayload['data'] as Map,
        );
        expect(firstData['action'], isNotNull);
        expect(firstData['duplicate'], isFalse);

        final second = await _send(
          handler,
          method: 'POST',
          path: '/webhooks/payments',
          body: webhookBody,
        );
        expect(second.statusCode, 200);
        final secondPayload = await _decodeJsonMap(second);
        final secondData = Map<String, Object?>.from(
          secondPayload['data'] as Map,
        );
        expect(secondData['duplicate'], isTrue);
        expect(secondData['action'], 'duplicate_ignored');
      },
    );

    test('pricing preview + coupon endpoints return envelope data', () async {
      final applyCoupon = await _send(
        handler,
        method: 'POST',
        path: '/marketplace/apply-coupon',
        userId: 'user-rider-1',
        headers: const <String, String>{'idempotency-key': 'idem-coupon-1'},
        body: const <String, Object?>{
          'org_id': 'org-demo-1',
          'coupon_code': 'LAUNCH50',
          'offer_id': 'offer_sedan_01',
          'seats': 2,
        },
      );
      expect(applyCoupon.statusCode, 200);
      final applyPayload = await _decodeJsonMap(applyCoupon);
      expect(applyPayload['ok'], isTrue);
      final applyData = Map<String, Object?>.from(applyPayload['data'] as Map);
      final preview = Map<String, Object?>.from(
        applyData['pricing_preview'] as Map,
      );
      expect((preview['coupon_discount_minor'] as int?) ?? 0, greaterThan(0));

      final previewResponse = await _send(
        handler,
        method: 'GET',
        path:
            '/marketplace/pricing/preview?org_id=org-demo-1&offer_id=offer_sedan_01&seats=2',
        userId: 'user-rider-1',
      );
      expect(previewResponse.statusCode, 200);
      final previewPayload = await _decodeJsonMap(previewResponse);
      expect(previewPayload['ok'], isTrue);
      final previewData = Map<String, Object?>.from(
        previewPayload['data'] as Map,
      );
      expect(previewData['base_minor'], greaterThan(0));
      expect(previewData['final_due_minor'], greaterThanOrEqualTo(0));
    });

    test('org credits and invoices endpoints return envelope data', () async {
      final create = await _send(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'user-rider-9',
        headers: const <String, String>{'idempotency-key': 'idem-org-9'},
        body: const <String, Object?>{
          'offerId': 'offer_sedan_01',
          'seatCount': 2,
          'org_id': 'org-credits-9',
        },
      );
      expect(create.statusCode, 200);

      final credits = await _send(
        handler,
        method: 'GET',
        path: '/api/orgs/org-credits-9/credits',
        userId: 'user-rider-9',
      );
      expect(credits.statusCode, 200);
      final creditsPayload = await _decodeJsonMap(credits);
      expect(creditsPayload['ok'], isTrue);
      final creditsData = Map<String, Object?>.from(
        creditsPayload['data'] as Map,
      );
      expect(creditsData['org_id'], 'org-credits-9');

      final invoices = await _send(
        handler,
        method: 'GET',
        path: '/api/orgs/org-credits-9/billing/invoices',
        userId: 'user-rider-9',
      );
      expect(invoices.statusCode, 200);
      final invoicesPayload = await _decodeJsonMap(invoices);
      expect(invoicesPayload['ok'], isTrue);
      expect(invoicesPayload['data'], isA<List<dynamic>>());
    });

    test('risk lock blocks marketplace mutation routes but not reads', () async {
      final adminToken = TokenService(
        secret: 'backend-test-secret',
      ).issueToken(userId: 'admin-1', role: 'admin');
      final adjustRisk = await _send(
        handler,
        method: 'POST',
        path: '/admin/risk/org/org-risk-locked/adjust',
        userId: 'admin-1',
        role: 'admin',
        headers: <String, String>{
          'idempotency-key': 'idem-risk-adjust',
          'authorization': 'Bearer $adminToken',
        },
        body: const <String, Object?>{'delta': 90, 'reason': 'risk_test'},
      );
      expect(adjustRisk.statusCode, 200);

      final blockedCreate = await _send(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'user-risk-1',
        headers: const <String, String>{'idempotency-key': 'idem-risk-1'},
        body: const <String, Object?>{
          'offerId': 'offer_sedan_01',
          'seatCount': 1,
          'org_id': 'org-risk-locked',
        },
      );
      expect(blockedCreate.statusCode, 403);
      final blockedPayload = await _decodeJsonMap(blockedCreate);
      expect(blockedPayload['error_code'], 'RISK_LOCKED');

      final readsStillAllowed = await _send(
        handler,
        method: 'GET',
        path:
            '/marketplace/pricing/preview?org_id=org-risk-locked&offer_id=offer_sedan_01&seats=1',
        userId: 'user-risk-1',
      );
      expect(readsStillAllowed.statusCode, 200);
    });
  });

  group('DbProvider postgres branch', () {
    test('postgres mode skips sqlite initialization path', () async {
      var sqliteOpenCalls = 0;
      var logMessage = '';
      final provider = DbProvider.forTesting(
        sqliteOpener: (_) async {
          sqliteOpenCalls += 1;
          return const _NoopDatabase();
        },
        logger: (message) => logMessage = message,
      );

      await provider.open(dbMode: BackendDbMode.postgres);

      expect(sqliteOpenCalls, 0);
      expect(
        logMessage,
        contains('db_mode=postgres: skipping sqlite initialization'),
      );
    });

    test('sqlite mode still invokes sqlite initialization path', () async {
      var sqliteOpenCalls = 0;
      final provider = DbProvider.forTesting(
        sqliteOpener: (_) async {
          sqliteOpenCalls += 1;
          return const _NoopDatabase();
        },
      );

      await provider.open(dbMode: BackendDbMode.sqlite);

      expect(sqliteOpenCalls, 1);
    });
  });
}

Handler _buildHandler() {
  return AppServer(
    db: const _NoopDatabase(),
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'postgres',
    environment: 'test',
    requestMetrics: RequestMetrics(),
    dbHealthCheck: () async => true,
    buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
    runtimeConfigSnapshot: const <String, Object?>{
      'environment': 'test',
      'db_mode': 'postgres',
      'db_schema': 'public',
    },
  ).buildHandler();
}

Future<Response> _send(
  Handler handler, {
  required String method,
  required String path,
  String? userId,
  String role = 'rider',
  Map<String, String>? headers,
  Map<String, Object?>? body,
}) async {
  var request = shelf.Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: <String, String>{'content-type': 'application/json', ...?headers},
    body: body == null ? '' : jsonEncode(body),
  );
  if (userId != null && userId.trim().isNotEmpty) {
    request = RequestContext.withContext(
      request,
      RequestContext(traceId: 'test-trace', userId: userId, role: role),
    );
  }
  return handler(request);
}

Future<Map<String, Object?>> _decodeJsonMap(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _EndpointCase {
  const _EndpointCase({required this.method, required this.path});

  final String method;
  final String path;
}

class _NoopDatabase implements Database {
  const _NoopDatabase();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) {
      return Future<void>.value();
    }
    throw UnsupportedError(
      'Unexpected sqlite access in test: ${invocation.memberName}',
    );
  }
}
