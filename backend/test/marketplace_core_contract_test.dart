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
  group('marketplace core v1 contract fixtures', () {
    late Handler handler;

    setUp(() {
      handler = _buildHandler();
    });

    test(
      'GET /marketplace/offers paginated response matches fixture',
      () async {
        final response = await _request(
          handler,
          method: 'GET',
          path: '/marketplace/offers?limit=2',
          headers: const <String, String>{'x-trace-id': 'fixture-trace-offers'},
        );

        expect(response.statusCode, 200);
        final payload = await _decodeBody(response);
        expect(payload, _loadFixture('offers_ok.json'));
      },
    );

    test('GET /marketplace/purchases/{id} response matches fixture', () async {
      const userId = 'fixture-user-read-1';
      const idempotencyKey = 'fixture-idem-read-1';
      final purchaseId = await _createPurchase(
        handler,
        userId: userId,
        idempotencyKey: idempotencyKey,
      );

      final response = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/purchases/$purchaseId',
        userId: userId,
        traceId: 'fixture-trace-purchase',
      );

      expect(response.statusCode, 200);
      final payload = await _decodeBody(response);
      final normalized = _normalizePayload(
        payload,
        purchaseId: purchaseId,
        normalizeTimestamps: true,
      );
      expect(normalized, _loadFixture('purchase_get_ok.json'));
    });

    test(
      'POST /marketplace/purchases/restore response matches fixture',
      () async {
        const userId = 'fixture-user-restore-1';
        const idempotencyKey = 'fixture-idem-restore-1';
        final purchaseId = await _createPurchase(
          handler,
          userId: userId,
          idempotencyKey: idempotencyKey,
        );

        final response = await _request(
          handler,
          method: 'POST',
          path: '/marketplace/purchases/restore',
          userId: userId,
          traceId: 'fixture-trace-restore',
          body: const <String, Object?>{'idempotencyKey': idempotencyKey},
        );

        expect(response.statusCode, 200);
        final payload = await _decodeBody(response);
        final normalized = _normalizePayload(
          payload,
          purchaseId: purchaseId,
          normalizeTimestamps: true,
        );
        expect(normalized, _loadFixture('restore_ok.json'));
      },
    );

    test(
      'GET /marketplace/timeline paginated response matches fixture',
      () async {
        const userId = 'fixture-user-timeline-1';
        const idempotencyKey = 'fixture-idem-timeline-1';
        final purchaseId = await _createPurchase(
          handler,
          userId: userId,
          idempotencyKey: idempotencyKey,
        );

        final seatUpdate = await _request(
          handler,
          method: 'PATCH',
          path: '/marketplace/purchases/$purchaseId/seats',
          userId: userId,
          traceId: 'fixture-trace-seat-update',
          body: const <String, Object?>{'seat_count': 3},
        );
        expect(seatUpdate.statusCode, 200);

        final response = await _request(
          handler,
          method: 'GET',
          path: '/marketplace/timeline?limit=2',
          userId: userId,
          traceId: 'fixture-trace-timeline',
        );

        expect(response.statusCode, 200);
        final payload = await _decodeBody(response);
        final normalized = _normalizePayload(
          payload,
          purchaseId: purchaseId,
          normalizeTimestamps: true,
        );
        expect(normalized, _loadFixture('timeline_ok.json'));
      },
    );

    test('invalid cursor returns validation fixture contract', () async {
      final response = await _request(
        handler,
        method: 'GET',
        path: '/marketplace/offers?cursor=not-a-valid-cursor!',
        headers: const <String, String>{'x-trace-id': 'fixture-trace-error'},
      );

      expect(response.statusCode, 400);
      final payload = await _decodeBody(response);
      expect(payload, _loadFixture('cursor_validation_err.json'));
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
    traceId: 'fixture-trace-create',
    headers: <String, String>{'idempotency-key': idempotencyKey},
    body: const <String, Object?>{'offerId': 'offer_sedan_01', 'seatCount': 2},
  );
  expect(response.statusCode, 200);
  final payload = await _decodeBody(response);
  final data = Map<String, Object?>.from(payload['data'] as Map);
  final purchaseId = (data['purchaseId'] as String?) ?? '';
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
  final file = File('test/fixtures/marketplace/$fileName');
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}

Map<String, Object?> _normalizePayload(
  Map<String, Object?> payload, {
  required String purchaseId,
  required bool normalizeTimestamps,
}) {
  final normalized = _normalizeValue(
    payload,
    purchaseId: purchaseId,
    normalizeTimestamps: normalizeTimestamps,
  );
  return Map<String, Object?>.from(normalized as Map);
}

Object? _normalizeValue(
  Object? value, {
  required String purchaseId,
  required bool normalizeTimestamps,
}) {
  if (value is List) {
    return value
        .map(
          (item) => _normalizeValue(
            item,
            purchaseId: purchaseId,
            normalizeTimestamps: normalizeTimestamps,
          ),
        )
        .toList(growable: false);
  }
  if (value is Map) {
    final normalized = <String, Object?>{};
    value.forEach((rawKey, rawValue) {
      final key = rawKey.toString();
      if (key == 'purchaseId' || key == 'purchase_id') {
        normalized[key] = '<purchase_id>';
        return;
      }
      if (normalizeTimestamps &&
          (key == 'createdAt' ||
              key == 'timestamp' ||
              key == 'latest_event_at')) {
        normalized[key] = '<timestamp>';
        return;
      }
      normalized[key] = _normalizeValue(
        rawValue,
        purchaseId: purchaseId,
        normalizeTimestamps: normalizeTimestamps,
      );
    });
    return normalized;
  }
  if (value is String && value == purchaseId) {
    return '<purchase_id>';
  }
  return value;
}
