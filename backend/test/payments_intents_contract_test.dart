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
  group('payments intents contract', () {
    test('POST /payments/intents creates intent and matches fixture', () async {
      final handler = _buildHandler(
        environmentMap: const <String, String>{
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'test-secret',
        },
      );
      const userId = 'payments-intent-user-create';
      final purchaseId = await _createPurchase(
        handler,
        userId: userId,
        idempotencyKey: 'fixture-intent-create-purchase',
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-create',
        headers: const <String, String>{
          'idempotency-key': 'fixture-intent-create-1',
        },
        body: <String, Object?>{'purchase_id': purchaseId},
      );

      expect(response.statusCode, 200);
      final payload = await _decodeBody(response);
      final normalized = _normalizeIntentPayload(payload);
      expect(normalized, _loadFixture('payment_intent_created_ok.json'));
    });

    test('GET /payments/intents/{id} matches fixture', () async {
      final handler = _buildHandler(
        environmentMap: const <String, String>{
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'test-secret',
        },
      );
      const userId = 'payments-intent-user-get';
      final purchaseId = await _createPurchase(
        handler,
        userId: userId,
        idempotencyKey: 'fixture-intent-get-purchase',
      );

      final createResponse = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-create-get',
        headers: const <String, String>{'idempotency-key': 'fixture-intent-2'},
        body: <String, Object?>{'purchase_id': purchaseId},
      );
      expect(createResponse.statusCode, 200);
      final createPayload = await _decodeBody(createResponse);
      final createdData = Map<String, Object?>.from(
        createPayload['data'] as Map,
      );
      final intentId = (createdData['id'] as String?) ?? '';
      expect(intentId.isNotEmpty, isTrue);

      final response = await _request(
        handler,
        method: 'GET',
        path: '/payments/intents/$intentId',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-get',
      );

      expect(response.statusCode, 200);
      final payload = await _decodeBody(response);
      final normalized = _normalizeIntentPayload(payload);
      expect(normalized, _loadFixture('payment_intent_get_ok.json'));
    });

    test('one active intent per purchase returns existing intent', () async {
      final handler = _buildHandler(
        environmentMap: const <String, String>{
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'test-secret',
        },
      );
      const userId = 'payments-intent-user-dedupe';
      final purchaseId = await _createPurchase(
        handler,
        userId: userId,
        idempotencyKey: 'fixture-intent-dedupe-purchase',
      );

      final first = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-dedupe-1',
        headers: const <String, String>{'idempotency-key': 'fixture-intent-3'},
        body: <String, Object?>{'purchase_id': purchaseId},
      );
      final second = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-dedupe-2',
        headers: const <String, String>{'idempotency-key': 'fixture-intent-4'},
        body: <String, Object?>{'purchase_id': purchaseId},
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      final firstBody = await _decodeBody(first);
      final secondBody = await _decodeBody(second);
      final firstData = Map<String, Object?>.from(firstBody['data'] as Map);
      final secondData = Map<String, Object?>.from(secondBody['data'] as Map);
      expect(secondData['id'], firstData['id']);
    });

    test('purchase not pending_payment returns conflict', () async {
      final handler = _buildHandler(
        environmentMap: const <String, String>{'PAYMENT_PROVIDER': 'manual'},
      );
      const userId = 'payments-intent-user-conflict';
      final purchaseId = await _createPurchase(
        handler,
        userId: userId,
        idempotencyKey: 'fixture-intent-conflict-purchase',
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: userId,
        traceId: 'fixture-trace-payment-intent-conflict',
        headers: const <String, String>{'idempotency-key': 'fixture-intent-5'},
        body: <String, Object?>{'purchase_id': purchaseId},
      );

      expect(response.statusCode, 409);
      final payload = await _decodeBody(response);
      expect(payload['ok'], isFalse);
      expect(payload['error_code'], 'CONFLICT');
    });

    test('missing purchase_id returns validation fixture', () async {
      final handler = _buildHandler(
        environmentMap: const <String, String>{
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'test-secret',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/payments/intents',
        userId: 'payments-intent-user-validation',
        traceId: 'fixture-trace-payment-intent-validation',
        headers: const <String, String>{'idempotency-key': 'fixture-intent-6'},
        body: const <String, Object?>{},
      );

      expect(response.statusCode, 400);
      final payload = await _decodeBody(response);
      expect(payload, _loadFixture('validation_err.json'));
    });
  });
}

Handler _buildHandler({required Map<String, String> environmentMap}) {
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
    environmentMap: environmentMap,
  ).buildHandler();
}

Future<String> _createPurchase(
  Handler handler, {
  required String userId,
  required String idempotencyKey,
}) async {
  final response = await _request(
    handler,
    method: 'POST',
    path: '/marketplace/purchases',
    userId: userId,
    traceId: 'fixture-trace-create-purchase',
    headers: <String, String>{'idempotency-key': idempotencyKey},
    body: const <String, Object?>{'offer_id': 'offer_sedan_01', 'quantity': 1},
  );
  expect(response.statusCode, 200);
  final payload = await _decodeBody(response);
  final data = Map<String, Object?>.from(payload['data'] as Map);
  final purchase = Map<String, Object?>.from(data['purchase'] as Map);
  final purchaseId = (purchase['purchase_id'] as String?) ?? '';
  expect(purchaseId.isNotEmpty, isTrue);
  return purchaseId;
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
  final file = File('test/fixtures/payments/$fileName');
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

Map<String, Object?> _normalizeIntentPayload(Map<String, Object?> payload) {
  final normalized = Map<String, Object?>.from(payload);
  final data = normalized['data'];
  if (data is Map) {
    final normalizedData = Map<String, Object?>.from(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
    normalizedData['id'] = '<intent_id>';
    normalized['data'] = normalizedData;
  }
  return normalized;
}
