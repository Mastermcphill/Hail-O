import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../marketplace/marketplace_offer_repository.dart';
import 'payment_provider.dart';

class StripePaymentProvider implements PaymentProvider {
  StripePaymentProvider({required String webhookSecret, Uuid? uuid})
    : _webhookSecret = webhookSecret.trim(),
      _uuid = uuid ?? const Uuid();

  final String _webhookSecret;
  final Uuid _uuid;

  @override
  String get provider => 'stripe';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    return PaymentCheckoutResult(
      provider: provider,
      status: 'PENDING',
      providerPaymentIntentId: 'stripe_${purchase.id}',
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
    final signatureHeader = (headers['stripe-signature'] ?? '').trim();
    final signatureValid = _verifySignature(
      rawBody: rawBody,
      signatureHeader: signatureHeader,
    );
    final rawEventType = (payload['type'] as String?)?.trim() ?? '';
    final eventType = _normalizeEventType(rawEventType);
    final dataObject = (payload['data'] is Map)
        ? (payload['data'] as Map)['object']
        : null;
    final purchaseId = _extractPurchaseId(dataObject);
    final providerEventId =
        (payload['id'] as String?)?.trim().isNotEmpty == true
        ? (payload['id'] as String).trim()
        : _uuid.v4();

    return PaymentWebhookEvent(
      provider: provider,
      providerEventId: providerEventId,
      eventType: eventType,
      signatureValid: signatureValid,
      purchaseId: purchaseId,
      payload: payload,
    );
  }

  bool _verifySignature({
    required String rawBody,
    required String signatureHeader,
  }) {
    if (signatureHeader.isEmpty || _webhookSecret.isEmpty) {
      return false;
    }
    final values = _parseStripeSignature(signatureHeader);
    final timestamp = values['t'] ?? '';
    final expectedSignature = values['v1'] ?? '';
    if (timestamp.isEmpty || expectedSignature.isEmpty) {
      return false;
    }
    final signedPayload = '$timestamp.$rawBody';
    final digest = Hmac(
      sha256,
      utf8.encode(_webhookSecret),
    ).convert(utf8.encode(signedPayload)).toString();
    return digest.toLowerCase() == expectedSignature.toLowerCase();
  }

  Map<String, String> _parseStripeSignature(String header) {
    final values = <String, String>{};
    for (final part in header.split(',')) {
      final tokens = part.split('=');
      if (tokens.length != 2) {
        continue;
      }
      values[tokens[0].trim()] = tokens[1].trim();
    }
    return values;
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

  String? _extractPurchaseId(Object? dataObject) {
    if (dataObject is! Map) {
      return null;
    }
    final metadata = dataObject['metadata'];
    if (metadata is Map) {
      final value = (metadata['purchase_id'] ?? metadata['purchaseId'])
          ?.toString()
          .trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String _normalizeEventType(String rawEventType) {
    final normalized = rawEventType.trim().toLowerCase();
    switch (normalized) {
      case 'payment_intent.succeeded':
      case 'charge.succeeded':
        return 'payment_succeeded';
      case 'payment_intent.payment_failed':
      case 'charge.failed':
        return 'payment_failed';
      default:
        return normalized.isEmpty ? 'payment_succeeded' : normalized;
    }
  }
}
