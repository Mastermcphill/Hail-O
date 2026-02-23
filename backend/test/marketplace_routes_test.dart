import 'dart:convert';

import 'package:hail_o_finance_core/sqlite_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../infra/db_provider.dart';
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
      const _EndpointCase(method: 'GET', path: '/marketplace/offers'),
      const _EndpointCase(
        method: 'GET',
        path: '/marketplace/offers/offer-basic/paywall',
      ),
      const _EndpointCase(
        method: 'GET',
        path: '/marketplace/purchases/restore?idempotencyKey=test-key',
      ),
      const _EndpointCase(method: 'GET', path: '/marketplace/purchases/p-123'),
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
      'POST /marketplace/purchases without Idempotency-Key still returns envelope',
      () async {
        final response = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          body: const <String, Object?>{
            'offerId': 'offer-basic',
            'seatCount': 2,
          },
        );

        expect(response.statusCode, 501);
        expect(response.headers['content-type'], contains('application/json'));
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isFalse);
        expect(payload['error_code'], 'NOT_IMPLEMENTED');
        expect((payload['trace_id'] as String?)?.isNotEmpty, isTrue);
      },
    );

    test(
      'POST /marketplace/purchases accepts Idempotency-Key and does not crash',
      () async {
        final response = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          headers: const <String, String>{
            'idempotency-key': 'purchase-idempotency-1',
          },
          body: const <String, Object?>{
            'offerId': 'offer-basic',
            'seatCount': 3,
          },
        );

        expect(response.statusCode, 501);
        expect(response.headers['x-idempotency-key'], 'purchase-idempotency-1');
        final payload = await _decodeJsonMap(response);
        expect(payload['ok'], isFalse);
        expect(payload['error_code'], 'NOT_IMPLEMENTED');
      },
    );

    test(
      'POST /marketplace/purchases invalid body returns VALIDATION_ERROR',
      () async {
        final response = await _send(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          body: const <String, Object?>{
            'offerId': 'offer-basic',
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
  Map<String, String>? headers,
  Map<String, Object?>? body,
}) async {
  return handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        ...?headers,
      },
      body: body == null ? '' : jsonEncode(body),
    ),
  );
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
