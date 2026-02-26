import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../server/app_server.dart';

void main() {
  group('payments webhook secret policy', () {
    const payload = <String, Object?>{
      'provider_event_id': 'evt-webhook-policy-1',
      'event_type': 'payment_succeeded',
      'purchase_id': '4fdd4a6f-63b1-4a9e-bcf6-36f18bb1988f',
      'amount_minor': 4200,
      'currency': 'NGN',
    };

    test(
      'valid x-webhook-signature is accepted when secret is configured',
      () async {
        const secret = 'webhook-secret-1';
        final handler = _buildHandler(
          environment: 'test',
          environmentMap: const <String, String>{
            'ENV': 'test',
            'PAYMENT_PROVIDER': 'manual',
            'PAYMENTS_WEBHOOK_SECRET': secret,
          },
        );

        final rawBody = jsonEncode(payload);
        final signature = Hmac(
          sha256,
          utf8.encode(secret),
        ).convert(utf8.encode(rawBody)).toString();
        final response = await _request(
          handler,
          method: 'POST',
          path: '/webhooks/payments',
          headers: <String, String>{'x-webhook-signature': signature},
          rawBody: rawBody,
        );

        expect(response.statusCode, 200);
        final envelope = await _decodeBody(response);
        expect(envelope['ok'], isTrue);
      },
    );

    test(
      'invalid x-webhook-signature is rejected when secret is configured',
      () async {
        final handler = _buildHandler(
          environment: 'test',
          environmentMap: const <String, String>{
            'ENV': 'test',
            'PAYMENT_PROVIDER': 'manual',
            'PAYMENTS_WEBHOOK_SECRET': 'webhook-secret-2',
          },
        );

        final response = await _request(
          handler,
          method: 'POST',
          path: '/webhooks/payments',
          headers: const <String, String>{
            'x-webhook-signature': 'bad-signature',
          },
          rawBody: jsonEncode(payload),
        );

        expect(response.statusCode, 401);
        final envelope = await _decodeBody(response);
        expect(envelope['ok'], isFalse);
        expect(envelope['error_code'], 'INVALID_WEBHOOK_SIGNATURE');
      },
    );

    test('invalid x-webhook-signature is forbidden in production', () async {
      final handler = _buildHandler(
        environment: 'production',
        environmentMap: const <String, String>{
          'ENV': 'production',
          'PAYMENT_PROVIDER': 'manual',
          'PAYMENTS_WEBHOOK_SECRET': 'webhook-secret-2',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        headers: const <String, String>{'x-webhook-signature': 'bad-signature'},
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 403);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['error_code'], 'INVALID_WEBHOOK_SIGNATURE');
    });

    test('missing webhook secret is rejected in production', () async {
      final handler = _buildHandler(
        environment: 'production',
        environmentMap: const <String, String>{
          'ENV': 'production',
          'PAYMENT_PROVIDER': 'manual',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 503);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['error_code'], 'WEBHOOK_CONFIG_ERROR');
    });

    test('missing webhook secret is allowed outside production', () async {
      final handler = _buildHandler(
        environment: 'development',
        environmentMap: const <String, String>{
          'ENV': 'development',
          'PAYMENT_PROVIDER': 'manual',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 200);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isTrue);
    });
  });

  group('paystack webhook signature policy', () {
    const payload = <String, Object?>{
      'event': 'charge.success',
      'data': <String, Object?>{
        'id': 'evt-paystack-policy-1',
        'metadata': <String, Object?>{
          'purchase_id': '4fdd4a6f-63b1-4a9e-bcf6-36f18bb1988f',
        },
      },
    };

    test(
      'valid x-paystack-signature is accepted when paystack secret is configured',
      () async {
        const webhookSecret = 'paystack-webhook-secret';
        final handler = _buildHandler(
          environment: 'test',
          environmentMap: const <String, String>{
            'ENV': 'test',
            'PAYMENT_PROVIDER': 'paystack',
            'PAYSTACK_SECRET_KEY': 'sk_test_key',
            'PAYSTACK_WEBHOOK_SECRET': webhookSecret,
          },
        );
        final rawBody = jsonEncode(payload);
        final signature = Hmac(
          sha512,
          utf8.encode(webhookSecret),
        ).convert(utf8.encode(rawBody)).toString();
        final response = await _request(
          handler,
          method: 'POST',
          path: '/webhooks/payments',
          headers: <String, String>{'x-paystack-signature': signature},
          rawBody: rawBody,
        );

        expect(response.statusCode, 200);
        final envelope = await _decodeBody(response);
        expect(envelope['ok'], isTrue);
      },
    );

    test('invalid x-paystack-signature is rejected', () async {
      final handler = _buildHandler(
        environment: 'test',
        environmentMap: const <String, String>{
          'ENV': 'test',
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'sk_test_key',
          'PAYSTACK_WEBHOOK_SECRET': 'paystack-webhook-secret-2',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        headers: const <String, String>{
          'x-paystack-signature': 'invalid-signature',
        },
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 401);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['error_code'], 'INVALID_WEBHOOK_SIGNATURE');
    });

    test('invalid x-paystack-signature is forbidden in production', () async {
      final handler = _buildHandler(
        environment: 'production',
        environmentMap: const <String, String>{
          'ENV': 'production',
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'sk_live_key',
          'PAYSTACK_WEBHOOK_SECRET': 'paystack-webhook-secret-2',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        headers: const <String, String>{
          'x-paystack-signature': 'invalid-signature',
        },
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 403);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['error_code'], 'INVALID_WEBHOOK_SIGNATURE');
    });

    test('missing paystack webhook secret is rejected in production', () async {
      final handler = _buildHandler(
        environment: 'production',
        environmentMap: const <String, String>{
          'ENV': 'production',
          'PAYMENT_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'sk_live_key',
        },
      );

      final response = await _request(
        handler,
        method: 'POST',
        path: '/webhooks/payments',
        rawBody: jsonEncode(payload),
      );

      expect(response.statusCode, 503);
      final envelope = await _decodeBody(response);
      expect(envelope['ok'], isFalse);
      expect(envelope['error_code'], 'WEBHOOK_CONFIG_ERROR');
    });
  });
}

Handler _buildHandler({
  required String environment,
  required Map<String, String> environmentMap,
}) {
  return AppServer(
    db: null,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'postgres',
    environment: environment,
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

Future<Response> _request(
  Handler handler, {
  required String method,
  required String path,
  Map<String, String>? headers,
  required String rawBody,
}) async {
  return await handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: <String, String>{
        'content-type': 'application/json',
        ...?headers,
      },
      body: rawBody,
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
