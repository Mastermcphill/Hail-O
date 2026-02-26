import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../marketplace/marketplace_offer_repository.dart';
import 'payment_provider.dart';

class PaystackPaymentProvider implements PaymentProvider {
  PaystackPaymentProvider({required String secretKey, Uuid? uuid})
    : _secretKey = secretKey.trim(),
      _uuid = uuid ?? const Uuid();

  final String _secretKey;
  final Uuid _uuid;

  @override
  String get provider => 'paystack';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    return PaymentCheckoutResult(
      provider: provider,
      status: 'PENDING',
      providerPaymentIntentId: 'paystack_${purchase.id}',
      raw: <String, Object?>{
        'purchase_id': purchase.id,
        'provider': provider,
        'status': 'PENDING',
      },
    );
  }

  @override
  Future<PaymentWebhookEvent> verifyAndParseWebhook({
    required Map<String, String> headers,
    required String rawBody,
  }) async {
    final payload = _decodeBody(rawBody);
    final signature = (headers['x-paystack-signature'] ?? '').trim();
    final signatureValid = _verifySignature(
      rawBody: rawBody,
      signature: signature,
    );
    final rawEventType = (payload['event'] as String?)?.trim() ?? '';
    final eventType = _normalizeEventType(rawEventType);
    final data = payload['data'];
    final purchaseId = _extractPurchaseId(data);
    final headerEventId = (headers['x-paystack-event-id'] ?? '').trim();
    final providerEventId =
        _extractEventId(data) ??
        (headerEventId.isNotEmpty ? headerEventId : _uuid.v4());

    return PaymentWebhookEvent(
      provider: provider,
      providerEventId: providerEventId,
      eventType: eventType,
      signatureValid: signatureValid,
      purchaseId: purchaseId,
      payload: payload,
    );
  }

  bool _verifySignature({required String rawBody, required String signature}) {
    if (signature.isEmpty || _secretKey.isEmpty) {
      return false;
    }
    final digest = Hmac(
      sha512,
      utf8.encode(_secretKey),
    ).convert(utf8.encode(rawBody)).toString();
    return digest.toLowerCase() == signature.toLowerCase();
  }

  Map<String, Object?> _decodeBody(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('webhook_body_must_be_json_object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _extractPurchaseId(Object? data) {
    if (data is! Map) {
      return null;
    }
    final metadata = data['metadata'];
    if (metadata is Map) {
      final value = (metadata['purchase_id'] ?? metadata['purchaseId'])
          ?.toString()
          .trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final direct = data['purchase_id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    return null;
  }

  String? _extractEventId(Object? data) {
    if (data is! Map) {
      return null;
    }
    final id = data['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      return id;
    }
    return null;
  }

  String _normalizeEventType(String rawEventType) {
    final normalized = rawEventType.trim().toLowerCase();
    switch (normalized) {
      case 'charge.success':
        return 'payment_succeeded';
      case 'charge.failed':
        return 'payment_failed';
      default:
        return normalized.isEmpty ? 'payment_succeeded' : normalized;
    }
  }
}
