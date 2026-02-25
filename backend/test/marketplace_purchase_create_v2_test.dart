import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../infra/request_context.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../server/app_server.dart';

void main() {
  group('marketplace core v2 create purchase', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    test(
      'creates purchase with offer_id + quantity and fixture contract',
      () async {
        final response = await _request(
          handler,
          method: 'POST',
          path: '/marketplace/purchases',
          userId: 'v2-create-user',
          traceId: 'fixture-trace-create-v2',
          headers: const <String, String>{
            'idempotency-key': 'v2-create-idem-1',
          },
          body: const <String, Object?>{
            'offer_id': 'offer_sedan_01',
            'quantity': 2,
            'client_reference': 'mobile-checkout-001',
          },
        );

        expect(response.statusCode, 200);
        final payload = await _decodeBody(response);
        final data = Map<String, Object?>.from(payload['data'] as Map);
        final purchase = Map<String, Object?>.from(data['purchase'] as Map);
        final normalized = _normalizePurchaseObject(purchase);
        expect(normalized, _loadFixture('purchase_created_ok.json'));
      },
    );

    test('idempotency returns same purchase for same user + key', () async {
      final first = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'v2-idem-user',
        traceId: 'fixture-trace-idem-first',
        headers: const <String, String>{'idempotency-key': 'v2-idem-key-1'},
        body: const <String, Object?>{
          'offer_id': 'offer_sedan_01',
          'quantity': 1,
          'client_reference': 'web-checkout-01',
        },
      );
      expect(first.statusCode, 200);
      final firstBody = await _decodeBody(first);
      final firstData = Map<String, Object?>.from(firstBody['data'] as Map);
      final firstPurchase = Map<String, Object?>.from(
        firstData['purchase'] as Map,
      );
      final firstPurchaseId = (firstPurchase['purchase_id'] as String?) ?? '';
      expect(firstPurchaseId.isNotEmpty, isTrue);

      final replay = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'v2-idem-user',
        traceId: 'fixture-trace-idem-replay',
        headers: const <String, String>{'idempotency-key': 'v2-idem-key-1'},
        body: const <String, Object?>{
          'offer_id': 'offer_sedan_01',
          'quantity': 9,
          'client_reference': 'should-not-change',
        },
      );
      expect(replay.statusCode, 200);
      final replayBody = await _decodeBody(replay);
      final replayData = Map<String, Object?>.from(replayBody['data'] as Map);
      final replayPurchase = Map<String, Object?>.from(
        replayData['purchase'] as Map,
      );
      final replayPurchaseId = (replayPurchase['purchase_id'] as String?) ?? '';
      expect(replayPurchaseId, firstPurchaseId);
    });

    test('invalid offer_id returns NOT_FOUND', () async {
      final response = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'v2-invalid-offer-user',
        traceId: 'fixture-trace-invalid-offer',
        headers: const <String, String>{
          'idempotency-key': 'v2-invalid-offer-1',
        },
        body: const <String, Object?>{
          'offer_id': 'offer_does_not_exist',
          'quantity': 1,
        },
      );
      expect(response.statusCode, 404);
      final payload = await _decodeBody(response);
      expect(payload['ok'], isFalse);
      expect(payload['error_code'], 'NOT_FOUND');
    });

    test('invalid quantity returns validation fixture', () async {
      final response = await _request(
        handler,
        method: 'POST',
        path: '/marketplace/purchases',
        userId: 'v2-invalid-qty-user',
        traceId: 'fixture-trace-validation',
        headers: const <String, String>{'idempotency-key': 'v2-invalid-qty-1'},
        body: const <String, Object?>{
          'offer_id': 'offer_sedan_01',
          'quantity': 0,
        },
      );
      expect(response.statusCode, 400);
      final payload = await _decodeBody(response);
      expect(payload, _loadFixture('validation_err.json'));
    });
  });
}

Handler _buildHandler() {
  return AppServer(
    db: null,
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
    environmentMap: const <String, String>{'PAYMENT_PROVIDER': 'manual'},
  ).buildHandler();
}

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  String? userId,
  String role = 'rider',
  String? traceId,
  Map<String, String>? headers,
  Map<String, Object?>? body,
}) async {
  final requestHeaders = <String, String>{'content-type': 'application/json'};
  if (traceId != null && traceId.trim().isNotEmpty) {
    requestHeaders['x-trace-id'] = traceId.trim();
  }
  requestHeaders.addAll(headers ?? const <String, String>{});
  var request = shelf.Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: requestHeaders,
    body: body == null ? '' : jsonEncode(body),
  );
  if (userId != null && userId.trim().isNotEmpty) {
    request = RequestContext.withContext(
      request,
      RequestContext(
        traceId: (traceId ?? 'fixture-trace-default').trim(),
        userId: userId,
        role: role,
      ),
    );
  }
  return handler(request);
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final raw = await response.readAsString();
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

Map<String, Object?> _loadFixture(String fileName) {
  final file = File('test/fixtures/marketplace/$fileName');
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

Map<String, Object?> _normalizePurchaseObject(Map<String, Object?> purchase) {
  final normalized = Map<String, Object?>.from(purchase);
  normalized['id'] = '<purchase_id>';
  normalized['purchase_id'] = '<purchase_id>';
  normalized['created_at'] = '<timestamp>';
  normalized['updated_at'] = '<timestamp>';
  return normalized;
}
