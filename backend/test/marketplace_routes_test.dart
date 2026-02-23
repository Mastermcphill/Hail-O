import 'dart:convert';

import 'package:hail_o_finance_core/sqlite_api.dart';
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

    final notImplementedCases = <_EndpointCase>[
      const _EndpointCase(
        method: 'PATCH',
        path: '/marketplace/purchases/p-123/seats',
      ),
      const _EndpointCase(
        method: 'PATCH',
        path: '/marketplace/purchases/p-123/assignments',
      ),
      const _EndpointCase(
        method: 'POST',
        path: '/marketplace/purchases/p-123/change-plan',
        headers: <String, String>{'idempotency-key': 'change-plan-key'},
      ),
      const _EndpointCase(
        method: 'GET',
        path: '/marketplace/purchases/p-123/timeline',
      ),
    ];

    for (final endpoint in notImplementedCases) {
      test(
        '${endpoint.method} ${endpoint.path} returns NOT_IMPLEMENTED envelope',
        () async {
          final response = await _send(
            handler,
            method: endpoint.method,
            path: endpoint.path,
            headers: endpoint.headers,
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
      RequestContext(traceId: 'test-trace', userId: userId, role: 'rider'),
    );
  }
  return handler(request);
}

Future<Map<String, Object?>> _decodeJsonMap(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

class _EndpointCase {
  const _EndpointCase({required this.method, required this.path, this.headers});

  final String method;
  final String path;
  final Map<String, String>? headers;
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
