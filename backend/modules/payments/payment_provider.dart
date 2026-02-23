import '../marketplace/marketplace_offer_repository.dart';

class PaymentCheckoutResult {
  const PaymentCheckoutResult({
    required this.provider,
    required this.status,
    required this.providerPaymentIntentId,
    required this.raw,
  });

  final String provider;
  final String status;
  final String providerPaymentIntentId;
  final Map<String, Object?> raw;
}

class PaymentWebhookEvent {
  const PaymentWebhookEvent({
    required this.provider,
    required this.providerEventId,
    required this.eventType,
    required this.signatureValid,
    required this.purchaseId,
    required this.payload,
  });

  final String provider;
  final String providerEventId;
  final String eventType;
  final bool signatureValid;
  final String? purchaseId;
  final Map<String, Object?> payload;
}

abstract class PaymentProvider {
  String get provider;

  Future<PaymentCheckoutResult> createCheckoutOrIntent({
    required MarketplacePurchaseRecord purchase,
  });

  Future<PaymentWebhookEvent> verifyAndParseWebhook({
    required Map<String, String> headers,
    required String rawBody,
  });
}
