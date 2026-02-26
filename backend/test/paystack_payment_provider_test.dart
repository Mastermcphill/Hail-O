import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../modules/marketplace/marketplace_offer_repository.dart';
import '../modules/payments/paystack_payment_provider.dart';

void main() {
  group('PaystackPaymentProvider initialization', () {
    test('falls back when secret key is not paystack formatted', () async {
      var callCount = 0;
      final provider = PaystackPaymentProvider(
        secretKey: 'test-secret',
        httpClient: MockClient((request) async {
          callCount += 1;
          return http.Response('{}', 500);
        }),
      );

      final result = await provider.createCheckoutOrIntent(
        purchase: _purchase(),
      );
      expect(callCount, 0);
      expect(result.provider, 'paystack');
      expect(result.status, 'PENDING');
      expect(result.providerPaymentIntentId, 'paystack_purchase_1');
      expect(result.raw['init_mode'], 'fallback');
    });

    test('uses paystack initialize endpoint and maps provider ref', () async {
      final provider = PaystackPaymentProvider(
        secretKey: 'sk_test_key',
        apiBaseUrl: 'https://api.paystack.co/',
        callbackUrl: 'https://app.hailo.dev/payments/callback',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.paystack.co/transaction/initialize',
          );
          expect(request.headers['authorization'], 'Bearer sk_test_key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['amount'], 4200);
          expect(body['currency'], 'NGN');
          expect(
            body['callback_url'],
            'https://app.hailo.dev/payments/callback',
          );
          final metadata = body['metadata'] as Map<String, dynamic>;
          expect(metadata['purchase_id'], 'purchase_1');
          return http.Response(
            jsonEncode(<String, Object?>{
              'status': true,
              'message': 'Authorization URL created',
              'data': <String, Object?>{
                'reference': 'pst_ref_123',
                'authorization_url':
                    'https://checkout.paystack.com/pst_ref_123',
                'access_code': 'pst_code_123',
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final result = await provider.createCheckoutOrIntent(
        purchase: _purchase(),
      );
      expect(result.provider, 'paystack');
      expect(result.status, 'PENDING');
      expect(result.providerPaymentIntentId, 'pst_ref_123');
      expect(result.raw['reference'], 'pst_ref_123');
      expect(
        result.raw['authorization_url'],
        'https://checkout.paystack.com/pst_ref_123',
      );
      expect(result.raw['access_code'], 'pst_code_123');
      expect(result.raw['init_mode'], 'paystack_api');
    });
  });
}

MarketplacePurchaseRecord _purchase() {
  return MarketplacePurchaseRecord(
    id: 'purchase_1',
    userId: 'user_1',
    offerId: 'offer_1',
    offerTitle: 'Offer',
    status: 'pending_payment',
    currency: 'NGN',
    totalAmountMinor: 4200,
    seatCount: 1,
    idempotencyKey: 'idem_1',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
