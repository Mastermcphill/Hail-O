import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

class PaymentCheckoutResult {
  const PaymentCheckoutResult({
    required this.success,
    required this.providerRef,
    required this.status,
    required this.amountMinor,
    required this.currency,
    this.metadata = const <String, Object?>{},
  });

  final bool success;
  final String providerRef;
  final String status;
  final int amountMinor;
  final String currency;
  final Map<String, Object?> metadata;
}

class PaymentWebhookVerificationResult {
  const PaymentWebhookVerificationResult({
    required this.verified,
    required this.provider,
    required this.providerEventId,
    required this.eventType,
    required this.payload,
    this.purchaseId,
    this.providerRef,
    this.amountMinor,
    this.currency,
    this.message,
  });

  final bool verified;
  final String provider;
  final String providerEventId;
  final String eventType;
  final String? purchaseId;
  final String? providerRef;
  final int? amountMinor;
  final String? currency;
  final Map<String, Object?> payload;
  final String? message;
}

abstract class PaymentProvider {
  String get providerName;

  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required Map<String, Object?> purchase,
  });

  Future<PaymentWebhookVerificationResult> verifyWebhook(Request request);
}

class ManualPaymentProvider implements PaymentProvider {
  ManualPaymentProvider({Uuid? uuid, String? webhookSecret})
    : _uuid = uuid ?? const Uuid(),
      _webhookSecret = webhookSecret ?? 'manual-secret';

  final Uuid _uuid;
  final String _webhookSecret;

  @override
  String get providerName => 'manual';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required Map<String, Object?> purchase,
  }) async {
    final purchaseId = (purchase['id'] as String?) ?? _uuid.v4();
    final amountMinor = (purchase['price_minor'] as num?)?.toInt() ?? 0;
    final currency = (purchase['currency'] as String?) ?? 'NGN';
    return PaymentCheckoutResult(
      success: true,
      providerRef: 'manual:$purchaseId',
      status: 'captured',
      amountMinor: amountMinor,
      currency: currency,
      metadata: <String, Object?>{
        'provider': 'manual',
        'purchase_id': purchaseId,
      },
    );
  }

  @override
  Future<PaymentWebhookVerificationResult> verifyWebhook(
    Request request,
  ) async {
    final signature = (request.headers['x-manual-signature'] ?? '').trim();
    if (signature.isNotEmpty && signature != _webhookSecret) {
      return const PaymentWebhookVerificationResult(
        verified: false,
        provider: 'manual',
        providerEventId: '',
        eventType: '',
        payload: <String, Object?>{},
        message: 'invalid_signature',
      );
    }
    final raw = await request.readAsString();
    final decoded = _decodePayload(raw);
    final providerEventId =
        (decoded['event_id'] as String?)?.trim().isNotEmpty == true
        ? (decoded['event_id'] as String).trim()
        : _uuid.v4();
    final eventType =
        (decoded['event_type'] as String?)?.trim().isNotEmpty == true
        ? (decoded['event_type'] as String).trim().toLowerCase()
        : 'payment_succeeded';
    return PaymentWebhookVerificationResult(
      verified: true,
      provider: 'manual',
      providerEventId: providerEventId,
      eventType: eventType,
      purchaseId: (decoded['purchase_id'] as String?)?.trim(),
      providerRef:
          (decoded['provider_ref'] as String?)?.trim() ??
          (decoded['payment_intent_id'] as String?)?.trim(),
      amountMinor: (decoded['amount_minor'] as num?)?.toInt(),
      currency: (decoded['currency'] as String?)?.trim(),
      payload: decoded,
    );
  }

  Map<String, Object?> _decodePayload(String raw) {
    if (raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map<Object?, Object?>) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, Object?>{};
  }
}

class PaystackPaymentProvider implements PaymentProvider {
  @override
  String get providerName => 'paystack';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required Map<String, Object?> purchase,
  }) async {
    final amountMinor = (purchase['price_minor'] as num?)?.toInt() ?? 0;
    final currency = (purchase['currency'] as String?) ?? 'NGN';
    return PaymentCheckoutResult(
      success: false,
      providerRef: '',
      status: 'not_implemented',
      amountMinor: amountMinor,
      currency: currency,
      metadata: const <String, Object?>{
        'reason': 'paystack_adapter_not_implemented',
      },
    );
  }

  @override
  Future<PaymentWebhookVerificationResult> verifyWebhook(
    Request request,
  ) async {
    await request.readAsString();
    return const PaymentWebhookVerificationResult(
      verified: false,
      provider: 'paystack',
      providerEventId: '',
      eventType: '',
      payload: <String, Object?>{},
      message: 'paystack_signature_verification_not_implemented',
    );
  }
}

class StripePaymentProvider implements PaymentProvider {
  @override
  String get providerName => 'stripe';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required Map<String, Object?> purchase,
  }) async {
    final amountMinor = (purchase['price_minor'] as num?)?.toInt() ?? 0;
    final currency = (purchase['currency'] as String?) ?? 'NGN';
    return PaymentCheckoutResult(
      success: false,
      providerRef: '',
      status: 'not_implemented',
      amountMinor: amountMinor,
      currency: currency,
      metadata: const <String, Object?>{
        'reason': 'stripe_adapter_not_implemented',
      },
    );
  }

  @override
  Future<PaymentWebhookVerificationResult> verifyWebhook(
    Request request,
  ) async {
    await request.readAsString();
    return const PaymentWebhookVerificationResult(
      verified: false,
      provider: 'stripe',
      providerEventId: '',
      eventType: '',
      payload: <String, Object?>{},
      message: 'stripe_signature_verification_not_implemented',
    );
  }
}
