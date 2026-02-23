import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../marketplace/marketplace_offer_repository.dart';
import 'payment_provider.dart';

class ManualPaymentProvider implements PaymentProvider {
  ManualPaymentProvider({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  String get provider => 'manual';

  @override
  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  }) async {
    return PaymentCheckoutResult(
      provider: provider,
      status: 'SUCCEEDED',
      providerPaymentIntentId: 'manual_${purchase.id}',
      raw: <String, Object?>{
        'purchase_id': purchase.id,
        'provider': provider,
        'status': 'SUCCEEDED',
      },
    );
  }

  @override
  Future<PaymentWebhookEvent> verifyAndParseWebhook({
    required Map<String, String> headers,
    required String rawBody,
  }) async {
    Map<String, Object?> payload = <String, Object?>{};
    if (rawBody.trim().isNotEmpty) {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const FormatException('webhook_body_must_be_json_object');
      }
      payload = Map<String, Object?>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final providerEventId =
        (payload['provider_event_id'] as String?)?.trim() ??
        (payload['event_id'] as String?)?.trim() ??
        (headers['x-provider-event-id'] ?? '').trim();

    final eventType =
        (payload['event_type'] as String?)?.trim() ??
        (payload['type'] as String?)?.trim() ??
        'payment_succeeded';
    final purchaseId = (payload['purchase_id'] as String?)?.trim();
    final normalizedPurchaseId = (purchaseId == null || purchaseId.isEmpty)
        ? null
        : purchaseId;

    return PaymentWebhookEvent(
      provider: provider,
      providerEventId: providerEventId.isEmpty ? _uuid.v4() : providerEventId,
      eventType: eventType,
      signatureValid: true,
      purchaseId: normalizedPurchaseId,
      payload: payload,
    );
  }
}
